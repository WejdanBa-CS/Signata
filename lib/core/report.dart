/// Tamper-evident verification report — Dart port of the website's
/// `em-report.ts`. The body is canonicalised (deterministic key order),
/// hashed with SHA-256 and sealed with a keyed digest; any edit to the
/// exported JSON invalidates the seal.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

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

/// Builds a sealed, verifiable report from a body.
SealedReport sealReport(ReportBody body) {
  final nonce = _nonce();
  final canonical = canonicalize(body.toJson());
  final bodyDigest = _sha256Hex(canonical);
  final signature =
      _hmacHex('$reportVersion|$nonce', '$canonical|$bodyDigest');
  return SealedReport(
    body: body,
    seal: {
      'algorithm': 'SHA-256 + HMAC-SHA-256',
      'canonicalization': 'sorted-keys-json',
      'nonce': nonce,
      'bodyDigest': bodyDigest,
      'signature': signature,
      'fingerprint':
          '${signature.substring(0, 4)}-${signature.substring(4, 8)}-${signature.substring(8, 12)}',
    },
  );
}

/// Recomputes the seal — returns false if the body was altered.
bool verifySealedReport(SealedReport sealed) {
  final canonical = canonicalize(sealed.body.toJson());
  final bodyDigest = _sha256Hex(canonical);
  if (bodyDigest != sealed.seal['bodyDigest']) return false;
  final signature = _hmacHex(
    '$reportVersion|${sealed.seal['nonce']}',
    '$canonical|$bodyDigest',
  );
  return signature == sealed.seal['signature'];
}

String reportFileName(String subject) {
  var safe = subject
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (safe.isEmpty) safe = 'asset';
  return 'signata-report-$safe.json';
}
