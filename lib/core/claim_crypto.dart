/// Account-bound claim authentication for Signata fingerprints.
///
/// New payloads carry `alg: hmac-sha256` + `kid` + `signature` (HMAC).
/// Legacy FNV-16 payloads (no `alg`) still verify as self-consistent only.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'auth.dart';
import 'fingerprint.dart';
import 'secure_store.dart';

const String claimAlgHmac = 'hmac-sha256';
const String claimAlgFnv16 = 'fnv16';
const int claimPayloadVersion = 2;

enum ClaimStatus {
  /// No recoverable payload.
  missing,

  /// Payload parsed but the signature/mac does not check out.
  present,

  /// Legacy FNV or structural digest matches (no account authentication).
  selfConsistent,

  /// HMAC verifies with the current account key.
  authenticated,

  /// HMAC payload issued under a different key id.
  foreignKey,
}

class ClaimKey {
  const ClaimKey({required this.bytes, required this.kid});

  final Uint8List bytes;
  final String kid;

  /// First 8 hex chars of SHA-256(key).
  static String kidFor(Uint8List key) =>
      sha256.convert(key).toString().substring(0, 8).toUpperCase();

  static ClaimKey generate() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    return ClaimKey(bytes: bytes, kid: kidFor(bytes));
  }

  /// Deterministic key for unit tests.
  static ClaimKey fromSeed(String seed) {
    final bytes = Uint8List.fromList(sha256.convert(utf8.encode(seed)).bytes);
    return ClaimKey(bytes: bytes, kid: kidFor(bytes));
  }
}

class SignedClaim {
  const SignedClaim({
    required this.signature,
    required this.alg,
    required this.kid,
    required this.version,
  });

  final String signature;
  final String alg;
  final String kid;
  final int version;

  Map<String, dynamic> toFields() => {
        'alg': alg,
        'kid': kid,
        'v': version,
        'signature': signature,
      };
}

class ClaimCrypto {
  static String hmacHex(ClaimKey key, String canonical) =>
      Hmac(sha256, key.bytes)
          .convert(utf8.encode(canonical))
          .toString()
          .toUpperCase();

  static String mediaCanonical({
    required String owner,
    required String asset,
    required String issued,
  }) =>
      '$owner|$asset|$issued';

  static String structuralCanonical({
    required String owner,
    required String document,
    required String issued,
    required String structureCanonical,
    required int originalLength,
    required String identifier,
  }) =>
      '$owner|$document|$issued|$structureCanonical|$originalLength|$identifier';

  static SignedClaim signMedia(
    ClaimKey key, {
    required String owner,
    required String asset,
    required String issued,
  }) {
    final canonical = mediaCanonical(owner: owner, asset: asset, issued: issued);
    return SignedClaim(
      signature: hmacHex(key, canonical),
      alg: claimAlgHmac,
      kid: key.kid,
      version: claimPayloadVersion,
    );
  }

  static SignedClaim signStructural(
    ClaimKey key, {
    required String owner,
    required String document,
    required String issued,
    required String structureCanonical,
    required int originalLength,
    required String identifier,
  }) {
    final canonical = structuralCanonical(
      owner: owner,
      document: document,
      issued: issued,
      structureCanonical: structureCanonical,
      originalLength: originalLength,
      identifier: identifier,
    );
    return SignedClaim(
      signature: hmacHex(key, canonical),
      alg: claimAlgHmac,
      kid: key.kid,
      version: claimPayloadVersion,
    );
  }

  /// Legacy FNV signature used when no account key is available.
  static SignedClaim signMediaLegacy({
    required String owner,
    required String asset,
    required String issued,
  }) =>
      SignedClaim(
        signature: fingerprint(mediaCanonical(
          owner: owner,
          asset: asset,
          issued: issued,
        )),
        alg: claimAlgFnv16,
        kid: '',
        version: 1,
      );

  static ClaimStatus evaluateMedia({
    required String owner,
    required String asset,
    required String issued,
    required String signature,
    String? alg,
    String? kid,
    ClaimKey? key,
  }) {
    final resolvedAlg =
        (alg == null || alg.isEmpty) ? claimAlgFnv16 : alg;
    final canonical =
        mediaCanonical(owner: owner, asset: asset, issued: issued);

    if (resolvedAlg == claimAlgFnv16) {
      return signature == fingerprint(canonical)
          ? ClaimStatus.selfConsistent
          : ClaimStatus.present;
    }

    if (resolvedAlg != claimAlgHmac) return ClaimStatus.present;
    if (key == null) {
      return (kid != null && kid.isNotEmpty)
          ? ClaimStatus.foreignKey
          : ClaimStatus.present;
    }
    if (kid != null && kid.isNotEmpty && kid.toUpperCase() != key.kid) {
      return ClaimStatus.foreignKey;
    }
    return hmacHex(key, canonical) == signature.toUpperCase()
        ? ClaimStatus.authenticated
        : ClaimStatus.present;
  }

  static ClaimStatus evaluateStructural({
    required String owner,
    required String document,
    required String issued,
    required String structureCanonical,
    required int originalLength,
    required String identifier,
    required String recheckId,
    required bool structureMatch,
    String? signature,
    String? alg,
    String? kid,
    ClaimKey? key,
  }) {
    final digestOk = identifier.isNotEmpty &&
        recheckId == identifier &&
        structureMatch;
    if (!digestOk) {
      return identifier.isEmpty ? ClaimStatus.missing : ClaimStatus.present;
    }

    final resolvedAlg =
        (alg == null || alg.isEmpty) ? claimAlgFnv16 : alg;
    if (resolvedAlg != claimAlgHmac || signature == null || signature.isEmpty) {
      return ClaimStatus.selfConsistent;
    }

    if (key == null) return ClaimStatus.foreignKey;
    if (kid != null && kid.isNotEmpty && kid.toUpperCase() != key.kid) {
      return ClaimStatus.foreignKey;
    }

    final canonical = structuralCanonical(
      owner: owner,
      document: document,
      issued: issued,
      structureCanonical: structureCanonical,
      originalLength: originalLength,
      identifier: identifier,
    );
    return hmacHex(key, canonical) == signature.toUpperCase()
        ? ClaimStatus.authenticated
        : ClaimStatus.present;
  }

  static String describe(ClaimStatus status) {
    switch (status) {
      case ClaimStatus.missing:
        return 'No readable Signata fingerprint was found.';
      case ClaimStatus.present:
        return 'A fingerprint was found but the claim signature is invalid.';
      case ClaimStatus.selfConsistent:
        return 'Claim is self-consistent (legacy / unauthenticated).';
      case ClaimStatus.authenticated:
        return 'Authenticated with your Signata key.';
      case ClaimStatus.foreignKey:
        return 'Claim consistent but not signed with your Signata key.';
    }
  }
}

/// Loads or creates the per-account HMAC key in secure storage.
class AccountClaimKeys {
  AccountClaimKeys._();

  static final _secure = signataSecureStorage;

  static String _storageKey(String userId) => 'signata_claim_key_$userId';

  static Future<ClaimKey> forUser(String userId) async {
    final existing = await _secure.read(key: _storageKey(userId));
    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = Uint8List.fromList(base64Url.decode(existing));
        if (bytes.length == 32) {
          return ClaimKey(bytes: bytes, kid: ClaimKey.kidFor(bytes));
        }
      } catch (_) {}
    }
    final key = ClaimKey.generate();
    await _secure.write(
      key: _storageKey(userId),
      value: base64UrlEncode(key.bytes),
    );
    return key;
  }

  static Future<ClaimKey?> current() async {
    final user = AuthService.instance.user;
    if (user == null) return null;
    return forUser(user.id);
  }

  /// Exports the raw claim key (base64url) for an offline recovery kit.
  static Future<String?> exportCurrentKeyBase64() async {
    final user = AuthService.instance.user;
    if (user == null) return null;
    return _secure.read(key: _storageKey(user.id));
  }

  /// Overwrites the current account claim key (e.g. after device restore).
  /// Returns the key id (kid).
  static Future<String> importForCurrentUser(String base64UrlKey) async {
    final user = AuthService.instance.user;
    if (user == null) {
      throw StateError('Not signed in.');
    }
    late final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Url.decode(base64UrlKey.trim()));
    } catch (_) {
      throw ArgumentError('Claim key is not valid base64url.');
    }
    if (bytes.length != 32) {
      throw ArgumentError('Claim key must be 32 bytes.');
    }
    await _secure.write(
      key: _storageKey(user.id),
      value: base64UrlEncode(bytes),
    );
    return ClaimKey.kidFor(bytes);
  }

  static Future<void> deleteForUser(String userId) async {
    await _secure.delete(key: _storageKey(userId));
  }
}
