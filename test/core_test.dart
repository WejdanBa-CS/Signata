import 'dart:convert';
import 'dart:typed_data';

import 'package:echomark/core/fingerprint.dart';
import 'package:echomark/core/image_watermark.dart';
import 'package:echomark/core/pdf_fingerprint.dart';
import 'package:echomark/core/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('fingerprint', () {
    test('is deterministic and 16 hex chars', () {
      final a = fingerprint('Studio Nova|photo.png·900x600|2026-01-01');
      final b = fingerprint('Studio Nova|photo.png·900x600|2026-01-01');
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9A-F]{16}$')));
    });

    test('changes when input changes', () {
      expect(fingerprint('abc'), isNot(fingerprint('abd')));
    });
  });

  group('image watermark', () {
    Uint8List samplePng() {
      final image = img.Image(width: 120, height: 90);
      for (final p in image) {
        p.setRgba((p.x * 2) % 256, (p.y * 3) % 256, (p.x + p.y) % 256, 255);
      }
      return img.encodePng(image);
    }

    test('embed round trip verifies', () async {
      final outcome = await embedWatermark(
        fileBytes: samplePng(),
        owner: 'Studio Nova',
        fileName: 'sample.png',
      );
      expect(outcome.verified, isTrue);
      expect(outcome.recovered?.owner, 'Studio Nova');
      expect(outcome.recovered?.asset, 'sample.png\u00b7120x90');
      expect(outcome.recovered?.signatureValid, isTrue);
    });

    test('standalone extraction recovers a genuine payload', () async {
      final outcome = await embedWatermark(
        fileBytes: samplePng(),
        owner: 'Creator X',
        fileName: 'art.png',
      );
      final extracted = await extractWatermark(outcome.markedPng);
      final payload = WatermarkPayload.tryParse(extracted.raw);
      expect(payload, isNotNull);
      expect(payload!.owner, 'Creator X');
      expect(payload.signatureValid, isTrue);
    });

    test('unmarked image yields no payload', () async {
      final extracted = await extractWatermark(samplePng());
      expect(WatermarkPayload.tryParse(extracted.raw), isNull);
    });

    test('forged payload fails the signature recheck', () {
      final forged = WatermarkPayload.tryParse(jsonEncode({
        'owner': 'Thief',
        'asset': 'stolen.png·10x10',
        'issued': '2026-01-01T00:00:00Z',
        'signature': 'AAAAAAAAAAAAAAAA',
      }));
      expect(forged!.signatureValid, isFalse);
    });
  });

  group('pdf fingerprint', () {
    Uint8List samplePdf() => Uint8List.fromList(latin1.encode(
          '%PDF-1.4\n'
          '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
          '4 0 obj\n<< /Length 11 >>\nstream\nHello world\nendstream\nendobj\n'
          'xref\n0 5\ntrailer\n<< /Root 1 0 R >>\n'
          'startxref\n300\n%%EOF\n',
        ));

    test('embed round trip verifies', () async {
      final outcome = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Studio Nova',
        fileName: 'doc.pdf',
      );
      expect(outcome.verified, isTrue);
      expect(outcome.structureMatch, isTrue);
      expect(outcome.recovered?.owner, 'Studio Nova');
      expect(outcome.recovered?.structure.version, '1.4');
      expect(outcome.recovered?.structure.pages, 1);
    });

    test('standalone verification of a delivered file passes', () async {
      final embedded = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Studio Nova',
        fileName: 'doc.pdf',
      );
      final verified = await verifyPdfFingerprint(embedded.markedBytes);
      expect(verified.verified, isTrue);
      expect(verified.recovered?.identifier, embedded.payload.identifier);
    });

    test('unmarked pdf yields no fingerprint', () async {
      final outcome = await verifyPdfFingerprint(samplePdf());
      expect(outcome.recovered, isNull);
      expect(outcome.verified, isFalse);
    });

    test('tampered identifier fails verification', () async {
      final embedded = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Studio Nova',
        fileName: 'doc.pdf',
      );
      // Forge the payload: change the owner but keep the identifier.
      final text = latin1.decode(embedded.markedBytes);
      final markIndex = text.lastIndexOf(pdfMark);
      final original = embedded.markedBytes.sublist(0, markIndex - 1);
      final payload = embedded.recovered!;
      final forged = jsonEncode({
        'owner': 'Thief',
        'document': payload.document,
        'issued': payload.issued,
        'structure': payload.structure.toJson(),
        'identifier': payload.identifier,
      });
      final tampered =
          embedPdfIdentifier(Uint8List.fromList(original), forged);
      final outcome = await verifyPdfFingerprint(tampered);
      expect(outcome.verified, isFalse);
    });

    test('non-pdf input throws', () async {
      expect(
        () => verifyPdfFingerprint(
            Uint8List.fromList(latin1.encode('hello world'))),
        throwsA(isA<NotAPdfException>()),
      );
    });
  });

  group('sealed report', () {
    ReportBody body() => const ReportBody(
          medium: 'image',
          subject: 'sample.png',
          owner: 'Studio Nova',
          verified: true,
          issued: '2026-01-01T00:00:00Z',
          generated: '2026-01-02T00:00:00Z',
          evidence: {'method': 'LSB pixel-domain watermark', 'roundTripMs': 12},
        );

    test('seal verifies and has a fingerprint', () {
      final sealed = sealReport(body());
      expect(verifySealedReport(sealed), isTrue);
      expect(sealed.fingerprint, matches(RegExp(r'^[0-9A-F]{4}(-[0-9A-F]{4}){2}$')));
    });

    test('altered body invalidates the seal', () {
      final sealed = sealReport(body());
      final tampered = SealedReport(
        body: const ReportBody(
          medium: 'image',
          subject: 'sample.png',
          owner: 'Someone Else',
          verified: true,
          issued: '2026-01-01T00:00:00Z',
          generated: '2026-01-02T00:00:00Z',
          evidence: {'method': 'LSB pixel-domain watermark', 'roundTripMs': 12},
        ),
        seal: sealed.seal,
      );
      expect(verifySealedReport(tampered), isFalse);
    });

    test('canonicalize sorts keys recursively', () {
      expect(
        canonicalize({'b': 1, 'a': {'d': true, 'c': null}}),
        '{"a":{"c":null,"d":true},"b":1}',
      );
    });
  });
}
