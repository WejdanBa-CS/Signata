/// PDF structural fingerprinting — Dart port of the website prototype.
///
/// Injects a comment claim before the last `%%EOF` and appends a trailing
/// Signata marker. Payloads carry HMAC structural signatures when an account
/// key is available.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;

import 'claim_crypto.dart';

const String pdfMark = '%%Signata:';
const String pdfCommentMark = '% Signata-Claim: ';

String _bytesToText(Uint8List bytes) => latin1.decode(bytes);

/// Mirrors the website's `textToBytes` (each UTF-16 code unit masked to 8 bits).
Uint8List _textToBytes(String text) {
  final out = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    out[i] = text.codeUnitAt(i) & 0xff;
  }
  return out;
}

int _countMatches(String text, RegExp pattern) =>
    pattern.allMatches(text).length;

class PdfStructure {
  const PdfStructure({
    required this.version,
    required this.bytes,
    required this.pages,
    required this.objects,
    required this.streams,
    required this.xrefs,
    required this.linearized,
    required this.encrypted,
  });

  final String version;
  final int bytes;
  final int pages;
  final int objects;
  final int streams;
  final int xrefs;
  final bool linearized;
  final bool encrypted;

  Map<String, dynamic> toJson() => {
        'version': version,
        'bytes': bytes,
        'pages': pages,
        'objects': objects,
        'streams': streams,
        'xrefs': xrefs,
        'linearized': linearized,
        'encrypted': encrypted,
      };

  String get canonical => jsonEncode(toJson());

  static PdfStructure? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return PdfStructure(
      version: value['version'] as String? ?? 'unknown',
      bytes: (value['bytes'] as num?)?.toInt() ?? 0,
      pages: (value['pages'] as num?)?.toInt() ?? 0,
      objects: (value['objects'] as num?)?.toInt() ?? 0,
      streams: (value['streams'] as num?)?.toInt() ?? 0,
      xrefs: (value['xrefs'] as num?)?.toInt() ?? 0,
      linearized: value['linearized'] as bool? ?? false,
      encrypted: value['encrypted'] as bool? ?? false,
    );
  }
}

PdfStructure analyzePdf(String text, int byteLength) {
  final head = text.substring(0, math.min(9, text.length));
  final version =
      RegExp(r'%PDF-(\d\.\d)').firstMatch(head)?.group(1) ?? 'unknown';
  return PdfStructure(
    version: version,
    bytes: byteLength,
    pages: math.max(_countMatches(text, RegExp(r'/Type\s*/Page[^s]')), 1),
    objects: _countMatches(text, RegExp(r'\d+\s+\d+\s+obj\b')),
    streams: _countMatches(text, RegExp(r'\bstream\b')),
    xrefs: _countMatches(text, RegExp(r'\bxref\b')),
    linearized: text.contains(RegExp(r'/Linearized')),
    encrypted: text.contains(RegExp(r'/Encrypt\b')),
  );
}

String pdfDigest(String input) =>
    crypto.sha256.convert(_textToBytes(input)).toString().toUpperCase();

class PdfPayload {
  const PdfPayload({
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
  final PdfStructure structure;
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

  static PdfPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final structure = PdfStructure.fromJson(map['structure']);
      if (structure == null) return null;
      return PdfPayload(
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

  String structuralIdentifier() => identifier ?? pdfDigest(digestInput());

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

/// Injects a comment claim before the last `%%EOF`, then appends the trailing marker.
Uint8List embedPdfIdentifier(Uint8List source, String payload) {
  final encoded = base64Encode(utf8.encode(payload));
  final text = _bytesToText(source);
  final eofIndex = text.lastIndexOf('%%EOF');
  if (eofIndex >= 0) {
    final comment = '$pdfCommentMark$encoded\n';
    final commentBytes = _textToBytes(comment);
    final before = source.sublist(0, eofIndex);
    final after = source.sublist(eofIndex);
    final withComment = Uint8List(
      before.length + commentBytes.length + after.length,
    );
    withComment.setAll(0, before);
    withComment.setAll(before.length, commentBytes);
    withComment.setAll(before.length + commentBytes.length, after);
    source = withComment;
  }

  final tail = _textToBytes('\n$pdfMark$encoded\n%%EOF\n');
  final out = Uint8List(source.length + tail.length);
  out.setAll(0, source);
  out.setAll(source.length, tail);
  return out;
}

String? _extractTrailingMarker(String text) {
  final index = text.lastIndexOf(pdfMark);
  if (index == -1) return null;
  final start = index + pdfMark.length;
  final end = text.indexOf('\n', start);
  final encoded = text.substring(start, end == -1 ? text.length : end).trim();
  try {
    return utf8.decode(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

String? _extractCommentMarker(String text) {
  final index = text.lastIndexOf(pdfCommentMark);
  if (index == -1) return null;
  final start = index + pdfCommentMark.length;
  final end = text.indexOf('\n', start);
  final encoded = text.substring(start, end == -1 ? text.length : end).trim();
  try {
    return utf8.decode(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

String? extractPdfIdentifier(String text) =>
    _extractTrailingMarker(text) ?? _extractCommentMarker(text);

class PdfEmbedOutcome {
  const PdfEmbedOutcome({
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
  final PdfPayload payload;
  final PdfPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
  final ClaimStatus claimStatus;
  final int originalLength;
}

class PdfVerifyOutcome {
  const PdfVerifyOutcome({
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
    required this.claimStatus,
    required this.originalLength,
  });

  final PdfPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
  final ClaimStatus claimStatus;
  final int originalLength;
}

class NotAPdfException implements Exception {
  const NotAPdfException();

  @override
  String toString() => 'That file is not a valid PDF document.';
}

ClaimKey? _claimKeyFromArgs(Uint8List? keyBytes, String? kid) {
  if (keyBytes == null || keyBytes.length != 32) return null;
  return ClaimKey(bytes: keyBytes, kid: kid ?? ClaimKey.kidFor(keyBytes));
}

PdfPayload _buildPayload({
  required String owner,
  required String fileName,
  required String issued,
  required PdfStructure structure,
  required int contentBytes,
  ClaimKey? claimKey,
}) {
  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  final identifier = pdfDigest(
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
    return PdfPayload(
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

  return PdfPayload(
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
  PdfPayload payload,
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

  final originalBytes = source.sublist(0, originalLength);
  final originalText = _bytesToText(originalBytes);
  final structure = analyzePdf(originalText, originalLength);
  final recheckId = pdfDigest(payload.digestInput());
  final structureMatch =
      structure.canonical == payload.structure.canonical;
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

PdfEmbedOutcome _pdfEmbedTask(
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
  final text = _bytesToText(source);
  if (!text.startsWith('%PDF-')) throw const NotAPdfException();

  final contentBytes = source.length;
  final structure = analyzePdf(text, contentBytes);
  final payload = _buildPayload(
    owner: owner,
    fileName: fileName,
    issued: issued,
    structure: structure,
    contentBytes: contentBytes,
    claimKey: claimKey,
  );

  final marked = embedPdfIdentifier(source, jsonEncode(payload.toJson()));
  final deliveredText = _bytesToText(marked);
  final raw = extractPdfIdentifier(deliveredText);
  final recovered = PdfPayload.tryParse(raw);

  if (recovered == null) {
    return PdfEmbedOutcome(
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
  return PdfEmbedOutcome(
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

PdfVerifyOutcome _pdfVerifyTask(
  ({Uint8List source, Uint8List? keyBytes, String? kid}) args,
) {
  final (:source, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);
  final text = _bytesToText(source);
  if (!text.startsWith('%PDF-')) throw const NotAPdfException();

  final raw = extractPdfIdentifier(text);
  final recovered = PdfPayload.tryParse(raw);
  if (recovered == null) {
    return PdfVerifyOutcome(
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
  return PdfVerifyOutcome(
    recovered: recovered,
    raw: raw,
    recheckId: eval.recheckId,
    structureMatch: eval.structureMatch,
    verified: eval.verified,
    claimStatus: eval.claimStatus,
    originalLength: recovered.contentBytes,
  );
}

Future<PdfEmbedOutcome> embedPdfFingerprint({
  required Uint8List source,
  required String owner,
  required String fileName,
  ClaimKey? claimKey,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(
    _pdfEmbedTask,
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

Future<PdfVerifyOutcome> verifyPdfFingerprint(
  Uint8List source, {
  ClaimKey? claimKey,
}) =>
    compute(
      _pdfVerifyTask,
      (
        source: source,
        keyBytes: claimKey?.bytes,
        kid: claimKey?.kid,
      ),
    );
