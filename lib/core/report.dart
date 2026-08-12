/// Tamper-evident verification report.
///
/// When an account [ClaimKey] is supplied, the seal uses HMAC with that key
/// (kid recorded in the seal). Without a key, a legacy nonce-HMAC is used and
/// marked `binding: unbound` — anyone can reseal those.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'claim_crypto.dart';

const String reportVersion = 'signata-report/1';

/// Deterministic JSON: object keys sorted recursively.
String canonicalize(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) return '[${value.map(canonicalize).join(',')}]';
  final map = (value as Map).cast<String, Object?>();
  final keys = map.keys.toList()..sort();
  final entries =
      keys.map((k) => '${jsonEncode(k)}:${canonicalize(map[k])}');
  return '{${entries.join(',')}}';
}

String _sha256Hex(String text) =>
    crypto.sha256.convert(utf8.encode(text)).toString().toUpperCase();

String _hmacHex(String key, String text) =>
    crypto.Hmac(crypto.sha256, utf8.encode(key))
        .convert(utf8.encode(text))
        .toString()
        .toUpperCase();

String _hmacHexBytes(Uint8List key, String text) =>
    crypto.Hmac(crypto.sha256, key)
        .convert(utf8.encode(text))
        .toString()
        .toUpperCase();

class ReportBody {
  const ReportBody({
    required this.medium,
    required this.subject,
    required this.owner,
    required this.verified,
    required this.issued,
    required this.generated,
    required this.evidence,
  });

  final String medium;
  final String subject;
  final String owner;
  final bool verified;
  final String issued;
  final String generated;
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => {
        'medium': medium,
        'subject': subject,
        'owner': owner,
        'verified': verified,
        'issued': issued,
        'generated': generated,
        'evidence': evidence,
      };
}

class SealedReport {
  const SealedReport({required this.body, required this.seal});

  final ReportBody body;
  final Map<String, Object?> seal;

  String get fingerprint => seal['fingerprint'] as String;

  Map<String, Object?> toJson() => {
        'format': reportVersion,
        'report': body.toJson(),
        'seal': seal,
      };

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

String _nonce() {
  final rng = Random.secure();
  final bytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

/// Builds a sealed report. Prefer passing [claimKey] so the seal is
/// account-bound and not forgeable with only the report JSON.
SealedReport sealReport(ReportBody body, {ClaimKey? claimKey}) {
  final nonce = _nonce();
  final canonical = canonicalize(body.toJson());
  final bodyDigest = _sha256Hex(canonical);
  final String signature;
  final String binding;
  String? kid;
  if (claimKey != null) {
    signature = _hmacHexBytes(
      claimKey.bytes,
      '$reportVersion|$nonce|$canonical|$bodyDigest',
    );
    binding = 'account-key';
    kid = claimKey.kid;
  } else {
    signature =
        _hmacHex('$reportVersion|$nonce', '$canonical|$bodyDigest');
    binding = 'unbound';
  }
  return SealedReport(
    body: body,
    seal: {
      'algorithm': 'SHA-256 + HMAC-SHA-256',
      'canonicalization': 'sorted-keys-json',
      'binding': binding,
      if (kid != null) 'kid': kid,
      'nonce': nonce,
      'bodyDigest': bodyDigest,
      'signature': signature,
      'fingerprint':
          '${signature.substring(0, 4)}-${signature.substring(4, 8)}-${signature.substring(8, 12)}',
    },
  );
}

/// Recomputes the seal — returns false if the body was altered.
/// For account-bound seals, pass the same [claimKey] used to seal.
bool verifySealedReport(SealedReport sealed, {ClaimKey? claimKey}) {
  final canonical = canonicalize(sealed.body.toJson());
  final bodyDigest = _sha256Hex(canonical);
  if (bodyDigest != sealed.seal['bodyDigest']) return false;
  final nonce = sealed.seal['nonce'] as String? ?? '';
  final binding = sealed.seal['binding'] as String? ?? 'unbound';
  final String signature;
  if (binding == 'account-key') {
    if (claimKey == null) return false;
    if (sealed.seal['kid'] != null && sealed.seal['kid'] != claimKey.kid) {
      return false;
    }
    signature = _hmacHexBytes(
      claimKey.bytes,
      '$reportVersion|$nonce|$canonical|$bodyDigest',
    );
  } else {
    signature = _hmacHex(
      '$reportVersion|$nonce',
      '$canonical|$bodyDigest',
    );
  }
  return signature == sealed.seal['signature'];
}

String reportFileName(String subject) {
  var safe = subject
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (safe.isEmpty) safe = 'asset';
  return 'signata-report-$safe.json';
}
