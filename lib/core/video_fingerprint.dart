/// Video container fingerprinting — profiles an MP4/MOV file and embeds a
/// Signata claim in a custom `uuid` box plus a legacy trailing marker.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;

import 'claim_crypto.dart';

const String videoMark = '%%SignataVideo:';
final Uint8List signataVideoUuid =
    Uint8List.fromList(ascii.encode('SignataClaimV2!!'));

String _bytesToLatin1(Uint8List bytes) =>
    latin1.decode(bytes, allowInvalid: true);

Uint8List _latin1ToBytes(String text) {
  final out = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    out[i] = text.codeUnitAt(i) & 0xff;
  }
  return out;
}

class VideoStructure {
  const VideoStructure({
    required this.brand,
    required this.bytes,
    required this.atoms,
    required this.hasMoov,
    required this.hasMdat,
    required this.hasAudio,
    required this.hasVideo,
  });

  final String brand;
  final int bytes;
  final int atoms;
  final bool hasMoov;
  final bool hasMdat;
  final bool hasAudio;
  final bool hasVideo;

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'bytes': bytes,
        'atoms': atoms,
        'hasMoov': hasMoov,
        'hasMdat': hasMdat,
        'hasAudio': hasAudio,
        'hasVideo': hasVideo,
      };

  String get canonical => jsonEncode(toJson());

  static VideoStructure? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return VideoStructure(
      brand: value['brand'] as String? ?? 'unknown',
      bytes: (value['bytes'] as num?)?.toInt() ?? 0,
      atoms: (value['atoms'] as num?)?.toInt() ?? 0,
      hasMoov: value['hasMoov'] as bool? ?? false,
      hasMdat: value['hasMdat'] as bool? ?? false,
      hasAudio: value['hasAudio'] as bool? ?? false,
      hasVideo: value['hasVideo'] as bool? ?? false,
    );
  }
}

class VideoPayload {
  const VideoPayload({
    required this.owner,
    required this.document,
    required this.issued,
    required this.structure,
    required this.contentBytes,
    this.signature,
    this.alg,
    this.kid,
    this.version = 1,
    this.identifier,
  });

  final String owner;
  final String document;
  final String issued;
  final VideoStructure structure;
  final int contentBytes;
  final String? signature;
  final String? alg;
  final String? kid;
  final int version;

  /// Legacy structural digest (uppercase SHA-256 hex).
  final String? identifier;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'owner': owner,
      'document': document,
      'issued': issued,
      'structure': structure.toJson(),
      'contentBytes': contentBytes,
    };
    if (signature != null && signature!.isNotEmpty) {
      map['signature'] = signature;
    }
    if (alg != null && alg!.isNotEmpty) map['alg'] = alg;
    if (kid != null && kid!.isNotEmpty) map['kid'] = kid;
    if (version > 1) map['v'] = version;
    if (identifier != null && identifier!.isNotEmpty) {
      map['identifier'] = identifier;
    }
    return map;
  }

  static VideoPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final structure = VideoStructure.fromJson(map['structure']);
      if (structure == null) return null;
      return VideoPayload(
        owner: map['owner'] as String? ?? '',
        document: map['document'] as String? ?? '',
        issued: map['issued'] as String? ?? '',
        structure: structure,
        contentBytes: (map['contentBytes'] as num?)?.toInt() ??
            (map['originalLength'] as num?)?.toInt() ??
            structure.bytes,
        signature: map['signature'] as String?,
        alg: map['alg'] as String?,
        kid: map['kid'] as String?,
        version: (map['v'] as num?)?.toInt() ?? 1,
        identifier: map['identifier'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String digestInput() =>
      '$owner|$document|$issued|${structure.canonical}|$contentBytes';

  String structuralIdentifier() => identifier ?? videoDigest(digestInput());

  ClaimStatus statusWith(ClaimKey? key, {
    required String recheckId,
    required bool structureMatch,
  }) =>
      ClaimCrypto.evaluateStructural(
        owner: owner,
        document: document,
        issued: issued,
        structureCanonical: structure.canonical,
        originalLength: contentBytes,
        identifier: structuralIdentifier(),
        recheckId: recheckId,
        structureMatch: structureMatch,
        signature: signature,
        alg: alg,
        kid: kid,
        key: key,
      );
}

class NotAVideoException implements Exception {
  const NotAVideoException(
      [this.message = 'That file is not a supported MP4/MOV video.']);
  final String message;
  @override
  String toString() => message;
}

String videoDigest(String input) =>
    crypto.sha256.convert(_latin1ToBytes(input)).toString().toUpperCase();

VideoStructure analyzeVideo(Uint8List bytes) {
  if (bytes.length < 12) throw const NotAVideoException();

  final firstType = String.fromCharCodes(bytes.sublist(4, 8));
  if (firstType != 'ftyp' && firstType != 'wide' && firstType != 'mdat') {
    // Some files start with a free/skip atom; still accept if we later find moov.
  }

  var brand = 'unknown';
  var atoms = 0;
  var hasMoov = false;
  var hasMdat = false;
  var hasAudio = false;
  var hasVideo = false;

  var offset = 0;
  while (offset + 8 <= bytes.length && atoms < 4000) {
    final size = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (size < 8 && size != 1) break;

    atoms++;
    if (type == 'ftyp' && offset + 12 <= bytes.length) {
      brand = String.fromCharCodes(bytes.sublist(offset + 8, offset + 12));
    } else if (type == 'moov') {
      hasMoov = true;
    } else if (type == 'mdat') {
      hasMdat = true;
    }

    final end = size == 0
        ? bytes.length
        : (size == 1 && offset + 16 <= bytes.length)
            ? offset +
                ByteData.sublistView(bytes, offset + 8, offset + 16)
                    .getUint64(0, Endian.big)
            : offset + size;
    final windowEnd = end.clamp(0, bytes.length);
    final slice = _bytesToLatin1(bytes.sublist(offset, windowEnd));
    if (slice.contains('vide') ||
        slice.contains('avc1') ||
        slice.contains('hvc1')) {
      hasVideo = true;
    }
    if (slice.contains('soun') ||
        slice.contains('mp4a') ||
        slice.contains('opus')) {
      hasAudio = true;
    }

    if (size == 0) break;
    offset = windowEnd;
  }

  if (!hasMoov && !hasMdat && brand == 'unknown') {
    throw const NotAVideoException();
  }

  return VideoStructure(
    brand: brand.trim().isEmpty ? 'unknown' : brand,
    bytes: bytes.length,
    atoms: atoms,
    hasMoov: hasMoov,
    hasMdat: hasMdat,
    hasAudio: hasAudio,
    hasVideo: hasVideo,
  );
}

Uint8List _buildUuidBox(Uint8List payloadBytes) {
  final boxSize = 8 + 16 + payloadBytes.length;
  final box = Uint8List(boxSize);
  final header = ByteData(8);
  header.setUint32(0, boxSize, Endian.big);
  box.setAll(0, header.buffer.asUint8List());
  box.setAll(4, 'uuid'.codeUnits);
  box.setAll(8, signataVideoUuid);
  box.setAll(24, payloadBytes);
  return box;
}

Uint8List embedVideoIdentifier(Uint8List source, String payload) {
  final payloadBytes = utf8.encode(payload);
  final uuidBox = _buildUuidBox(payloadBytes);
  final encoded = base64Encode(utf8.encode(payload));
  final tail = _latin1ToBytes('\n$videoMark$encoded\n');
  final out = Uint8List(source.length + uuidBox.length + tail.length);
  out.setAll(0, source);
  out.setAll(source.length, uuidBox);
  out.setAll(source.length + uuidBox.length, tail);
  return out;
}

String? extractVideoUuidPayload(Uint8List bytes) {
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    final size = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    // Top-level boxes only need an 8-byte header; uuid payload needs 24+.
    if (size != 0 && size != 1 && size < 8) break;

    final end = size == 0
        ? bytes.length
        : (size == 1 && offset + 16 <= bytes.length)
            ? offset +
                ByteData.sublistView(bytes, offset + 8, offset + 16)
                    .getUint64(0, Endian.big)
            : offset + size;
    if (end <= offset || end > bytes.length) break;
    final windowEnd = end;

    if (type == 'uuid' && offset + 24 <= windowEnd) {
      final userType = bytes.sublist(offset + 8, offset + 24);
      if (userType.length == signataVideoUuid.length) {
        var matches = true;
        for (var i = 0; i < signataVideoUuid.length; i++) {
          if (userType[i] != signataVideoUuid[i]) {
            matches = false;
            break;
          }
        }
        if (matches && windowEnd > offset + 24) {
          try {
            return utf8.decode(bytes.sublist(offset + 24, windowEnd));
          } catch (_) {}
        }
      }
    }

    if (size == 0) break;
    offset = windowEnd;
  }
  return null;
}

String? extractVideoIdentifier(String text) {
  final index = text.lastIndexOf(videoMark);
  if (index == -1) return null;
  final start = index + videoMark.length;
  final end = text.indexOf('\n', start);
  final encoded = text.substring(start, end == -1 ? text.length : end).trim();
  try {
    return utf8.decode(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

String? extractVideoPayloadRaw(Uint8List bytes) {
  final uuidPayload = extractVideoUuidPayload(bytes);
  if (uuidPayload != null) return uuidPayload;
  return extractVideoIdentifier(_bytesToLatin1(bytes));
}

class VideoEmbedOutcome {
  const VideoEmbedOutcome({
    required this.markedBytes,
    required this.payload,
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
    required this.claimStatus,
    required this.originalLength,
  });

  final Uint8List markedBytes;
  final VideoPayload payload;
  final VideoPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
  final ClaimStatus claimStatus;
  final int originalLength;
}

class VideoVerifyOutcome {
  const VideoVerifyOutcome({
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
    required this.claimStatus,
    required this.originalLength,
  });

  final VideoPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
  final ClaimStatus claimStatus;
  final int originalLength;
}

ClaimKey? _claimKeyFromArgs(Uint8List? keyBytes, String? kid) {
  if (keyBytes == null || keyBytes.length != 32) return null;
  return ClaimKey(bytes: keyBytes, kid: kid ?? ClaimKey.kidFor(keyBytes));
}

VideoPayload _buildPayload({
  required String owner,
  required String fileName,
  required String issued,
  required VideoStructure structure,
  required int contentBytes,
  ClaimKey? claimKey,
}) {
  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  final identifier = videoDigest(
    '$resolvedOwner|$fileName|$issued|${structure.canonical}|$contentBytes',
  );

  if (claimKey != null) {
    final signed = ClaimCrypto.signStructural(
      claimKey,
      owner: resolvedOwner,
      document: fileName,
      issued: issued,
      structureCanonical: structure.canonical,
      originalLength: contentBytes,
      identifier: identifier,
    );
    return VideoPayload(
      owner: resolvedOwner,
      document: fileName,
      issued: issued,
      structure: structure,
      contentBytes: contentBytes,
      signature: signed.signature,
      alg: signed.alg,
      kid: signed.kid,
      version: signed.version,
      identifier: identifier,
    );
  }

  return VideoPayload(
    owner: resolvedOwner,
    document: fileName,
    issued: issued,
    structure: structure,
    contentBytes: contentBytes,
    identifier: identifier,
    version: 1,
  );
}

({String recheckId, bool structureMatch, ClaimStatus claimStatus, bool verified})
    _evaluatePayload(
  VideoPayload payload,
  Uint8List source,
  ClaimKey? claimKey,
) {
  final originalLength = payload.contentBytes;
  if (originalLength <= 0 || originalLength > source.length) {
    return (
      recheckId: '—',
      structureMatch: false,
      claimStatus: ClaimStatus.present,
      verified: false,
    );
  }

  final original = source.sublist(0, originalLength);
  final structure = analyzeVideo(original);
  final recheckId = videoDigest(payload.digestInput());
  final structureMatch = structure.canonical == payload.structure.canonical;
  final claimStatus = payload.statusWith(
    claimKey,
    recheckId: recheckId,
    structureMatch: structureMatch,
  );
  final verified = claimStatus == ClaimStatus.authenticated ||
      claimStatus == ClaimStatus.selfConsistent;

  return (
    recheckId: recheckId,
    structureMatch: structureMatch,
    claimStatus: claimStatus,
    verified: verified,
  );
}

VideoEmbedOutcome _embedTask(
  ({
    Uint8List source,
    String owner,
    String fileName,
    String issued,
    Uint8List? keyBytes,
    String? kid,
  }) args,
) {
  final (:source, :owner, :fileName, :issued, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);
  final contentBytes = source.length;
  final structure = analyzeVideo(source);
  final payload = _buildPayload(
    owner: owner,
    fileName: fileName,
    issued: issued,
    structure: structure,
    contentBytes: contentBytes,
    claimKey: claimKey,
  );

  final marked =
      embedVideoIdentifier(source, jsonEncode(payload.toJson()));
  final raw = extractVideoPayloadRaw(marked);
  final recovered = VideoPayload.tryParse(raw);

  if (recovered == null) {
    return VideoEmbedOutcome(
      markedBytes: marked,
      payload: payload,
      recovered: null,
      raw: raw,
      recheckId: '—',
      structureMatch: false,
      verified: false,
      claimStatus: ClaimStatus.missing,
      originalLength: contentBytes,
    );
  }

  final eval = _evaluatePayload(recovered, marked, claimKey);
  return VideoEmbedOutcome(
    markedBytes: marked,
    payload: payload,
    recovered: recovered,
    raw: raw,
    recheckId: eval.recheckId,
    structureMatch: eval.structureMatch,
    verified: eval.verified,
    claimStatus: eval.claimStatus,
    originalLength: contentBytes,
  );
}

VideoVerifyOutcome _verifyTask(
  ({Uint8List source, Uint8List? keyBytes, String? kid}) args,
) {
  final (:source, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);
  final raw = extractVideoPayloadRaw(source);
  final recovered = VideoPayload.tryParse(raw);
  if (recovered == null) {
    return VideoVerifyOutcome(
      recovered: null,
      raw: raw,
      recheckId: '—',
      structureMatch: false,
      verified: false,
      claimStatus: ClaimStatus.missing,
      originalLength: 0,
    );
  }

  final eval = _evaluatePayload(recovered, source, claimKey);
  return VideoVerifyOutcome(
    recovered: recovered,
    raw: raw,
    recheckId: eval.recheckId,
    structureMatch: eval.structureMatch,
    verified: eval.verified,
    claimStatus: eval.claimStatus,
    originalLength: recovered.contentBytes,
  );
}

Future<VideoEmbedOutcome> embedVideoFingerprint({
  required Uint8List source,
  required String owner,
  required String fileName,
  ClaimKey? claimKey,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(
    _embedTask,
    (
      source: source,
      owner: owner,
      fileName: fileName,
      issued: issued,
      keyBytes: claimKey?.bytes,
      kid: claimKey?.kid,
    ),
  );
}

Future<VideoVerifyOutcome> verifyVideoFingerprint(
  Uint8List source, {
  ClaimKey? claimKey,
}) =>
    compute(
      _verifyTask,
      (
        source: source,
        keyBytes: claimKey?.bytes,
        kid: claimKey?.kid,
      ),
    );
