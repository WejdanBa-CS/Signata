import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:signata/core/audio_watermark.dart';
import 'package:signata/core/claim_crypto.dart';
import 'package:signata/core/fingerprint.dart';
import 'package:signata/core/image_watermark.dart';
import 'package:signata/core/pdf_fingerprint.dart';
import 'package:signata/core/report.dart';
import 'package:signata/core/video_fingerprint.dart';

void main() {
  final alice = ClaimKey.fromSeed('alice-test-key');
  final bob = ClaimKey.fromSeed('bob-test-key');

  group('fingerprint', () {
    test('is deterministic and 16 hex chars', () {
      final a = fingerprint('Creator|photo.png·900x600|2026-01-01');
      final b = fingerprint('Creator|photo.png·900x600|2026-01-01');
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9A-F]{16}$')));
    });

    test('changes when input changes', () {
      expect(fingerprint('abc'), isNot(fingerprint('abd')));
    });
  });

  group('claim crypto', () {
    test('HMAC authenticates with the same key', () {
      final signed = ClaimCrypto.signMedia(
        alice,
        owner: 'Alice',
        asset: 'a.png·10x10',
        issued: '2026-01-01T00:00:00Z',
      );
      expect(
        ClaimCrypto.evaluateMedia(
          owner: 'Alice',
          asset: 'a.png·10x10',
          issued: '2026-01-01T00:00:00Z',
          signature: signed.signature,
          alg: signed.alg,
          kid: signed.kid,
          key: alice,
        ),
        ClaimStatus.authenticated,
      );
    });

    test('HMAC fails with a different key', () {
      final signed = ClaimCrypto.signMedia(
        alice,
        owner: 'Alice',
        asset: 'a.png·10x10',
        issued: '2026-01-01T00:00:00Z',
      );
      expect(
        ClaimCrypto.evaluateMedia(
          owner: 'Alice',
          asset: 'a.png·10x10',
          issued: '2026-01-01T00:00:00Z',
          signature: signed.signature,
          alg: signed.alg,
          kid: signed.kid,
          key: bob,
        ),
        ClaimStatus.foreignKey,
      );
    });

    test('legacy FNV is self-consistent only', () {
      final signed = ClaimCrypto.signMediaLegacy(
        owner: 'Alice',
        asset: 'a.png·10x10',
        issued: '2026-01-01T00:00:00Z',
      );
      expect(
        ClaimCrypto.evaluateMedia(
          owner: 'Alice',
          asset: 'a.png·10x10',
          issued: '2026-01-01T00:00:00Z',
          signature: signed.signature,
          alg: null,
          kid: null,
          key: alice,
        ),
        ClaimStatus.selfConsistent,
      );
    });
  });

  group('image watermark', () {
    Uint8List samplePng({int width = 120, int height = 90}) {
      final image = img.Image(width: width, height: height);
      for (final p in image) {
        p.setRgba((p.x * 2) % 256, (p.y * 3) % 256, (p.x + p.y) % 256, 255);
      }
      return img.encodePng(image);
    }

    test('embed round trip verifies with HMAC', () async {
      final outcome = await embedWatermark(
        fileBytes: samplePng(),
        owner: 'Creator',
        fileName: 'sample.png',
        claimKey: alice,
      );
      expect(outcome.verified, isTrue);
      expect(outcome.resized, isFalse);
      expect(outcome.claimStatus, ClaimStatus.authenticated);
      expect(outcome.recovered?.owner, 'Creator');
      expect(outcome.recovered?.asset, 'sample.png\u00b7120x90');
      expect(outcome.recovered?.isAuthentic(alice), isTrue);
      expect(outcome.recovered?.isAuthentic(bob), isFalse);
    });

    test('standalone extraction recovers an authenticated payload', () async {
      final outcome = await embedWatermark(
        fileBytes: samplePng(),
        owner: 'Creator X',
        fileName: 'art.png',
        claimKey: alice,
      );
      final extracted = await extractWatermark(outcome.markedPng);
      final payload = WatermarkPayload.tryParse(extracted.raw);
      expect(payload, isNotNull);
      expect(payload!.statusWith(alice), ClaimStatus.authenticated);
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

    test('legacy embed without key is self-consistent', () async {
      final outcome = await embedWatermark(
        fileBytes: samplePng(),
        owner: 'Legacy',
        fileName: 'old.png',
      );
      expect(outcome.claimStatus, ClaimStatus.selfConsistent);
      expect(outcome.recovered?.signatureValid, isTrue);
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

    test('embed round trip verifies with HMAC', () async {
      final outcome = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Creator',
        fileName: 'doc.pdf',
        claimKey: alice,
      );
      expect(outcome.verified, isTrue);
      expect(outcome.structureMatch, isTrue);
      expect(outcome.claimStatus, ClaimStatus.authenticated);
      expect(outcome.recovered?.owner, 'Creator');
      expect(outcome.recovered?.structure.version, '1.4');
      expect(outcome.recovered?.structure.pages, 1);
    });

    test('standalone verification of a delivered file passes', () async {
      final embedded = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Creator',
        fileName: 'doc.pdf',
        claimKey: alice,
      );
      final verified = await verifyPdfFingerprint(
        embedded.markedBytes,
        claimKey: alice,
      );
      expect(verified.verified, isTrue);
      expect(verified.claimStatus, ClaimStatus.authenticated);
      expect(verified.recovered?.identifier, embedded.payload.identifier);
    });

    test('redundant comment survives stripped trailing marker', () async {
      final embedded = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Creator',
        fileName: 'doc.pdf',
        claimKey: alice,
      );
      final text = latin1.decode(embedded.markedBytes);
      final markIndex = text.lastIndexOf(pdfMark);
      expect(markIndex, greaterThan(0));
      final withoutTrailing =
          Uint8List.fromList(embedded.markedBytes.sublist(0, markIndex - 1));
      expect(latin1.decode(withoutTrailing).contains(pdfCommentMark), isTrue);
      final verified = await verifyPdfFingerprint(
        withoutTrailing,
        claimKey: alice,
      );
      expect(verified.recovered, isNotNull);
      expect(verified.verified, isTrue);
      expect(verified.claimStatus, ClaimStatus.authenticated);
    });

    test('unmarked pdf yields no fingerprint', () async {
      final outcome = await verifyPdfFingerprint(samplePdf());
      expect(outcome.recovered, isNull);
      expect(outcome.verified, isFalse);
      expect(outcome.claimStatus, ClaimStatus.missing);
    });

    test('tampered identifier fails verification', () async {
      final embedded = await embedPdfFingerprint(
        source: samplePdf(),
        owner: 'Creator',
        fileName: 'doc.pdf',
        claimKey: alice,
      );
      final payload = embedded.recovered!;
      final forged = jsonEncode({
        'owner': 'Thief',
        'document': payload.document,
        'issued': payload.issued,
        'structure': payload.structure.toJson(),
        'identifier': payload.identifier,
        'contentBytes': payload.contentBytes,
        'signature': payload.signature,
        'alg': payload.alg,
        'kid': payload.kid,
        'v': payload.version,
      });
      final tampered = embedPdfIdentifier(samplePdf(), forged);
      final outcome = await verifyPdfFingerprint(tampered, claimKey: alice);
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

  group('audio watermark', () {
    Uint8List sampleWav({int samples = 8000}) {
      final dataSize = samples * 2;
      final bytes = BytesBuilder();
      void writeString(String s) => bytes.add(s.codeUnits);
      void writeUint32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        bytes.add(b.buffer.asUint8List());
      }

      void writeUint16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        bytes.add(b.buffer.asUint8List());
      }

      writeString('RIFF');
      writeUint32(36 + dataSize);
      writeString('WAVE');
      writeString('fmt ');
      writeUint32(16);
      writeUint16(1);
      writeUint16(1);
      writeUint32(44100);
      writeUint32(44100 * 2);
      writeUint16(2);
      writeUint16(16);
      writeString('data');
      writeUint32(dataSize);
      final pcm = Uint8List(dataSize);
      for (var i = 0; i < samples; i++) {
        final sample = (i * 13) & 0xffff;
        pcm[i * 2] = sample & 0xff;
        pcm[i * 2 + 1] = (sample >> 8) & 0xff;
      }
      bytes.add(pcm);
      return bytes.toBytes();
    }

    test('embed round trip verifies with HMAC', () async {
      final outcome = await embedAudioWatermark(
        fileBytes: sampleWav(),
        owner: 'Creator',
        fileName: 'clip.wav',
        claimKey: alice,
      );
      expect(outcome.verified, isTrue);
      expect(outcome.claimStatus, ClaimStatus.authenticated);
      expect(outcome.recovered?.owner, 'Creator');
      expect(outcome.recovered?.isAuthentic(alice), isTrue);
    });

    test('standalone extraction recovers an authenticated payload', () async {
      final embedded = await embedAudioWatermark(
        fileBytes: sampleWav(),
        owner: 'Creator X',
        fileName: 'voice.wav',
        claimKey: alice,
      );
      final extracted = await extractAudioWatermark(embedded.markedWav);
      final payload = AudioPayload.tryParse(extracted.raw);
      expect(payload, isNotNull);
      expect(payload!.statusWith(alice), ClaimStatus.authenticated);
      expect(payload.statusWith(bob), ClaimStatus.foreignKey);
    });
  });

  group('video fingerprint', () {
    Uint8List sampleMp4() {
      final bytes = BytesBuilder();
      void atom(String type, List<int> body) {
        final size = 8 + body.length;
        final header = ByteData(8)..setUint32(0, size, Endian.big);
        final out = Uint8List(size);
        out.setAll(0, header.buffer.asUint8List());
        out.setAll(4, type.codeUnits);
        out.setAll(8, body);
        bytes.add(out);
      }

      atom('ftyp', [...'isom'.codeUnits, 0, 0, 0, 0, ...'isom'.codeUnits]);
      atom('moov', [...'vide'.codeUnits, ...'soun'.codeUnits]);
      atom('mdat', List<int>.filled(64, 7));
      return bytes.toBytes();
    }

    test('embed round trip verifies with HMAC and uuid atom', () async {
      final outcome = await embedVideoFingerprint(
        source: sampleMp4(),
        owner: 'Creator',
        fileName: 'reel.mp4',
        claimKey: alice,
      );
      expect(outcome.verified, isTrue);
      expect(outcome.structureMatch, isTrue);
      expect(outcome.claimStatus, ClaimStatus.authenticated);
      expect(outcome.recovered?.owner, 'Creator');
      expect(extractVideoUuidPayload(outcome.markedBytes), isNotNull);
    });

    test('standalone verification of a delivered file passes', () async {
      final embedded = await embedVideoFingerprint(
        source: sampleMp4(),
        owner: 'Creator',
        fileName: 'reel.mp4',
        claimKey: alice,
      );
      final verified = await verifyVideoFingerprint(
        embedded.markedBytes,
        claimKey: alice,
      );
      expect(verified.verified, isTrue);
      expect(verified.claimStatus, ClaimStatus.authenticated);
      expect(verified.recovered?.identifier, embedded.payload.identifier);
    });

    test('legacy trailer still extracts when uuid box is removed', () async {
      final embedded = await embedVideoFingerprint(
        source: sampleMp4(),
        owner: 'Creator',
        fileName: 'reel.mp4',
        claimKey: alice,
      );
      final sourceLen = embedded.originalLength;
      final trailerOnly = Uint8List.fromList([
        ...embedded.markedBytes.sublist(0, sourceLen),
        ...latin1.encode(
          '\n$videoMark${base64Encode(utf8.encode(embedded.raw!))}\n',
        ),
      ]);
      expect(extractVideoUuidPayload(trailerOnly), isNull);
      expect(extractVideoIdentifier(latin1.decode(trailerOnly)), isNotNull);
      final verified = await verifyVideoFingerprint(
        trailerOnly,
        claimKey: alice,
      );
      expect(verified.recovered, isNotNull);
      expect(verified.verified, isTrue);
    });
  });

  group('sealed report', () {
    ReportBody body() => const ReportBody(
          medium: 'image',
          subject: 'sample.png',
          owner: 'Creator',
          verified: true,
          issued: '2026-01-01T00:00:00Z',
          generated: '2026-01-02T00:00:00Z',
          evidence: {'method': 'LSB pixel-domain watermark', 'roundTripMs': 12},
        );

    test('seal verifies and has a fingerprint', () {
      final sealed = sealReport(body());
      expect(verifySealedReport(sealed), isTrue);
      expect(
        sealed.fingerprint,
        matches(RegExp(r'^[0-9A-F]{4}(-[0-9A-F]{4}){2}$')),
      );
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
        canonicalize({
          'b': 1,
          'a': {'d': true, 'c': null}
        }),
        '{"a":{"c":null,"d":true},"b":1}',
      );
    });
  });
}
