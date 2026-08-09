/// Video container fingerprinting — profiles an MP4/MOV file and hides a
/// trailing Signata identifier (same pattern as the PDF prototype).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;

const String videoMark = '%%SignataVideo:';

String _bytesToLatin1(Uint8List bytes) => latin1.decode(bytes, allowInvalid: true);

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
    required this.identifier,
  });

  final String owner;
  final String document;
  final String issued;
  final VideoStructure structure;
  final String identifier;

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'document': document,
        'issued': issued,
        'structure': structure.toJson(),
        'identifier': identifier,
      };

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
        identifier: map['identifier'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  String digestInput(int originalLength) =>
      '$owner|$document|$issued|${structure.canonical}|$originalLength';
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

  // ISO BMFF: [size:4][type:4]…  ftyp usually first.
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

    // Sample descriptions / handler hints inside this atom window.
    final end = size == 0
        ? bytes.length
        : (size == 1 && offset + 16 <= bytes.length)
            ? offset +
                ByteData.sublistView(bytes, offset + 8, offset + 16)
                    .getUint64(0, Endian.big)
            : offset + size;
    final windowEnd = end.clamp(0, bytes.length);
    final slice = _bytesToLatin1(bytes.sublist(offset, windowEnd));
    if (slice.contains('vide') || slice.contains('avc1') || slice.contains('hvc1')) {
      hasVideo = true;
    }
    if (slice.contains('soun') || slice.contains('mp4a') || slice.contains('opus')) {
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

Uint8List embedVideoIdentifier(Uint8List source, String payload) {
  final encoded = base64Encode(utf8.encode(payload));
  final tail = _latin1ToBytes('\n$videoMark$encoded\n');
  final out = Uint8List(source.length + tail.length);
  out.setAll(0, source);
  out.setAll(source.length, tail);
  return out;
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

class VideoEmbedOutcome {
  const VideoEmbedOutcome({
    required this.markedBytes,
    required this.payload,
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
  });

  final Uint8List markedBytes;
  final VideoPayload payload;
  final VideoPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
}

class VideoVerifyOutcome {
  const VideoVerifyOutcome({
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
  });

  final VideoPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
}

VideoEmbedOutcome _embedTask(
    ({Uint8List source, String owner, String fileName, String issued}) args) {
  final (:source, :owner, :fileName, :issued) = args;
  final structure = analyzeVideo(source);
  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  final identifier = videoDigest(
    '$resolvedOwner|$fileName|$issued|${structure.canonical}|${source.length}',
  );
  final payload = VideoPayload(
    owner: resolvedOwner,
    document: fileName,
    issued: issued,
    structure: structure,
    identifier: identifier,
  );

  final marked = embedVideoIdentifier(source, jsonEncode(payload.toJson()));
  final deliveredText = _bytesToLatin1(marked);
  final raw = extractVideoIdentifier(deliveredText);
  final recovered = VideoPayload.tryParse(raw);
  final recheckId = recovered == null
      ? '—'
      : videoDigest(recovered.digestInput(source.length));
  final structureMatch =
      recovered != null && recovered.structure.canonical == structure.canonical;
  final verified = recovered != null &&
      recheckId == recovered.identifier &&
      structureMatch;

  return VideoEmbedOutcome(
    markedBytes: marked,
    payload: payload,
    recovered: recovered,
    raw: raw,
    recheckId: recheckId,
    structureMatch: structureMatch,
    verified: verified,
  );
}

VideoVerifyOutcome _verifyTask(Uint8List source) {
  final text = _bytesToLatin1(source);
  final raw = extractVideoIdentifier(text);
  final recovered = VideoPayload.tryParse(raw);
  if (recovered == null) {
    return const VideoVerifyOutcome(
      recovered: null,
      raw: null,
      recheckId: '—',
      structureMatch: false,
      verified: false,
    );
  }

  final markIndex = text.lastIndexOf(videoMark);
  final originalLength = markIndex > 0 ? markIndex - 1 : source.length;
  final original = source.sublist(0, originalLength);
  final structure = analyzeVideo(original);
  final recheckId = videoDigest(recovered.digestInput(originalLength));
  final structureMatch = recovered.structure.canonical == structure.canonical;
  final verified = recheckId == recovered.identifier && structureMatch;

  return VideoVerifyOutcome(
    recovered: recovered,
    raw: raw,
    recheckId: recheckId,
    structureMatch: structureMatch,
    verified: verified,
  );
}

Future<VideoEmbedOutcome> embedVideoFingerprint({
  required Uint8List source,
  required String owner,
  required String fileName,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(_embedTask,
      (source: source, owner: owner, fileName: fileName, issued: issued));
}

Future<VideoVerifyOutcome> verifyVideoFingerprint(Uint8List source) =>
    compute(_verifyTask, source);
