/// PDF structural fingerprinting — Dart port of the website prototype.
///
/// The identifier format uses a trailing Signata marker (`%%Signata:`
/// trailing marker carrying base64 JSON), so documents fingerprinted in the
/// app verify on the website and vice versa.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;

const String pdfMark = '%%Signata:';

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

  /// Key order matches the website's `JSON.stringify(structure)` so digests
  /// computed on either side agree.
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

/// Derives a structural profile from the raw PDF text.
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

/// SHA-256 hex digest (uppercase), byte-compatible with the website's digest.
String pdfDigest(String input) =>
    crypto.sha256.convert(_textToBytes(input)).toString().toUpperCase();

class PdfPayload {
  const PdfPayload({
    required this.owner,
    required this.document,
    required this.issued,
    required this.structure,
    required this.identifier,
  });

  final String owner;
  final String document;
  final String issued;
  final PdfStructure structure;
  final String identifier;

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'document': document,
        'issued': issued,
        'structure': structure.toJson(),
        'identifier': identifier,
      };

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
        identifier: map['identifier'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  String digestInput(int originalTextLength) =>
      '$owner|$document|$issued|${structure.canonical}|$originalTextLength';
}

/// Appends the identifier after %%EOF — trailing bytes are ignored by readers.
Uint8List embedPdfIdentifier(Uint8List source, String payload) {
  final encoded = base64Encode(utf8.encode(payload));
  final tail = _textToBytes('\n$pdfMark$encoded\n%%EOF\n');
  final out = Uint8List(source.length + tail.length);
  out.setAll(0, source);
  out.setAll(source.length, tail);
  return out;
}

String? extractPdfIdentifier(String text) {
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

/* --------------------------- high-level ops --------------------------- */

class PdfEmbedOutcome {
  const PdfEmbedOutcome({
    required this.markedBytes,
    required this.payload,
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
  });

  final Uint8List markedBytes;
  final PdfPayload payload;
  final PdfPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
}

class PdfVerifyOutcome {
  const PdfVerifyOutcome({
    required this.recovered,
    required this.raw,
    required this.recheckId,
    required this.structureMatch,
    required this.verified,
  });

  final PdfPayload? recovered;
  final String? raw;
  final String recheckId;
  final bool structureMatch;
  final bool verified;
}

class NotAPdfException implements Exception {
  const NotAPdfException();

  @override
  String toString() => 'That file is not a valid PDF document.';
}

PdfEmbedOutcome _pdfEmbedTask(
    ({Uint8List source, String owner, String fileName, String issued}) args) {
  final (:source, :owner, :fileName, :issued) = args;
  final text = _bytesToText(source);
  if (!text.startsWith('%PDF-')) throw const NotAPdfException();

  final structure = analyzePdf(text, source.length);
  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();

  final identifier = pdfDigest(
    '$resolvedOwner|$fileName|$issued|${structure.canonical}|${text.length}',
  );
  final payload = PdfPayload(
    owner: resolvedOwner,
    document: fileName,
    issued: issued,
    structure: structure,
    identifier: identifier,
  );

  final marked = embedPdfIdentifier(source, jsonEncode(payload.toJson()));

  // Read back from the delivered file, exactly as a verifier would.
  final deliveredText = _bytesToText(marked);
  final raw = extractPdfIdentifier(deliveredText);
  final recovered = PdfPayload.tryParse(raw);

  final recheckId =
      recovered == null ? '—' : pdfDigest(recovered.digestInput(text.length));
  final structureMatch =
      recovered != null && recovered.structure.canonical == structure.canonical;
  final verified = recovered != null &&
      recheckId == recovered.identifier &&
      structureMatch;

  return PdfEmbedOutcome(
    markedBytes: marked,
    payload: payload,
    recovered: recovered,
    raw: raw,
    recheckId: recheckId,
    structureMatch: structureMatch,
    verified: verified,
  );
}

PdfVerifyOutcome _pdfVerifyTask(Uint8List source) {
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
    );
  }

  // The marker tail starts with "\n%%Signata:", so everything before it is
  // the original document as it existed when the identifier was derived.
  final markIndex = text.lastIndexOf(pdfMark);
  final originalLength = markIndex > 0 ? markIndex - 1 : text.length;
  final originalText = text.substring(0, originalLength);

  final structure = analyzePdf(originalText, originalLength);
  final recheckId = pdfDigest(recovered.digestInput(originalLength));
  final structureMatch = recovered.structure.canonical == structure.canonical;
  final verified = recheckId == recovered.identifier && structureMatch;

  return PdfVerifyOutcome(
    recovered: recovered,
    raw: raw,
    recheckId: recheckId,
    structureMatch: structureMatch,
    verified: verified,
  );
}

/// Fingerprints [source] and round-trip verifies the delivered file.
Future<PdfEmbedOutcome> embedPdfFingerprint({
  required Uint8List source,
  required String owner,
  required String fileName,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(_pdfEmbedTask,
      (source: source, owner: owner, fileName: fileName, issued: issued));
}

/// Verifies a standalone PDF: recovers the identifier, recomputes the digest
/// and structural profile from the document itself, and compares.
Future<PdfVerifyOutcome> verifyPdfFingerprint(Uint8List source) =>
    compute(_pdfVerifyTask, source);
