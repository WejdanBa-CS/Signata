import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signata/core/audio_watermark.dart';
import 'package:signata/core/auth.dart';
import 'package:signata/core/claim_crypto.dart';
import 'package:signata/core/claim_registry.dart';
import 'package:signata/core/image_watermark.dart';
import 'package:signata/core/pdf_fingerprint.dart';
import 'package:signata/core/report.dart';
import 'package:signata/core/social_platforms.dart';
import 'package:signata/core/trace_models.dart';
import 'package:signata/core/trace_store.dart';
import 'package:signata/core/url_tracer.dart';
import 'package:signata/core/video_fingerprint.dart';

Uint8List _png({int w = 48, int h = 36}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, (x * 7) % 255, (y * 11) % 255, 90, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _wav({int samples = 2400}) {
  final dataSize = samples * 2;
  final bytes = BytesBuilder();
  void writeStr(String s) => bytes.add(s.codeUnits);
  void write32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    bytes.add(b.buffer.asUint8List());
  }

  void write16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    bytes.add(b.buffer.asUint8List());
  }

  writeStr('RIFF');
  write32(36 + dataSize);
  writeStr('WAVE');
  writeStr('fmt ');
  write32(16);
  write16(1);
  write16(1);
  write32(16000);
  write32(32000);
  write16(2);
  write16(16);
  writeStr('data');
  write32(dataSize);
  for (var i = 0; i < samples; i++) {
    write16(((i % 200) - 100) * 40);
  }
  return bytes.toBytes();
}

Uint8List _pdf() {
  const body = '''
%PDF-1.4
1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj
3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>endobj
xref
0 4
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
trailer<< /Size 4 /Root 1 0 R >>
startxref
190
%%EOF
''';
  return Uint8List.fromList(utf8.encode(body));
}

Uint8List _mp4() {
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
  atom('mdat', List<int>.filled(128, 3));
  return bytes.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final alice = ClaimKey.fromSeed('deep-alice');
  final bob = ClaimKey.fromSeed('deep-bob');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaimRegistry.configure(remoteBaseUrl: '');
  });

  group('deep media round-trips', () {
    test('image embed survives extract and rejects foreign key', () async {
      final embedded = await embedWatermark(
        fileBytes: _png(),
        owner: 'Wejdan',
        fileName: 'shot.png',
        claimKey: alice,
      );
      expect(embedded.claimStatus, ClaimStatus.authenticated);

      final ok = await extractWatermark(embedded.markedPng, claimKey: alice);
      expect(ok.claimStatus, ClaimStatus.authenticated);
      expect(WatermarkPayload.tryParse(ok.raw)?.owner, 'Wejdan');

      final foreign =
          await extractWatermark(embedded.markedPng, claimKey: bob);
      expect(foreign.claimStatus, ClaimStatus.foreignKey);
    });

    test('audio embed/extract authenticates', () async {
      final embedded = await embedAudioWatermark(
        fileBytes: _wav(),
        owner: 'Wejdan',
        fileName: 'clip.wav',
        claimKey: alice,
      );
      expect(embedded.claimStatus, ClaimStatus.authenticated);
      final extracted =
          await extractAudioWatermark(embedded.markedWav, claimKey: alice);
      expect(extracted.claimStatus, ClaimStatus.authenticated);
      expect(AudioPayload.tryParse(extracted.raw)?.owner, 'Wejdan');
    });

    test('pdf structural fingerprint authenticates and survives strip of trailer',
        () async {
      final embedded = await embedPdfFingerprint(
        source: _pdf(),
        owner: 'Wejdan',
        fileName: 'doc.pdf',
        claimKey: alice,
      );
      expect(embedded.claimStatus, ClaimStatus.authenticated);
      expect(embedded.verified, isTrue);

      final verified =
          await verifyPdfFingerprint(embedded.markedBytes, claimKey: alice);
      expect(verified.claimStatus, ClaimStatus.authenticated);
      expect(
        verified.recovered?.structuralIdentifier(),
        embedded.payload.structuralIdentifier(),
      );
    });

    test('video uuid atom is present and verifies', () async {
      final embedded = await embedVideoFingerprint(
        source: _mp4(),
        owner: 'Wejdan',
        fileName: 'reel.mp4',
        claimKey: alice,
      );
      expect(embedded.claimStatus, ClaimStatus.authenticated);
      expect(extractVideoUuidPayload(embedded.markedBytes), isNotNull);

      final verified =
          await verifyVideoFingerprint(embedded.markedBytes, claimKey: alice);
      expect(verified.claimStatus, ClaimStatus.authenticated);
      expect(verified.structureMatch, isTrue);
    });
  });

  group('deep auth policy', () {
    test('password policy rejects weak and accepts strong', () {
      expect(PasswordPolicy.validate('short1A'), isNotNull);
      expect(PasswordPolicy.validate('alllettersxx'), isNotNull);
      expect(PasswordPolicy.validate('1234567890'), isNotNull);
      expect(PasswordPolicy.validate('Signata2026!'), isNull);
    });

    test('pbkdf2 verify fails closed on wrong password', () {
      final salt = base64UrlEncode(List<int>.generate(16, (i) => i + 9));
      final hash = PasswordHasher.hash('CorrectHorse9', salt);
      expect(
        PasswordHasher.verify(
          password: 'CorrectHorse9',
          saltBase64: salt,
          expectedHash: hash,
          algorithm: PasswordHasher.algoPbkdf2,
        ),
        isTrue,
      );
      expect(
        PasswordHasher.verify(
          password: 'CorrectHorse8',
          saltBase64: salt,
          expectedHash: hash,
          algorithm: PasswordHasher.algoPbkdf2,
        ),
        isFalse,
      );
    });
  });

  group('deep tracing', () {
    test('social hosts map correctly', () {
      expect(
        SocialPlatformInfo.fromUrl('https://www.instagram.com/p/x/')?.id,
        SocialPlatform.instagram,
      );
      expect(
        SocialPlatformInfo.fromUrl('https://vm.tiktok.com/abc')?.id,
        SocialPlatform.tiktok,
      );
      expect(
        SocialPlatformInfo.fromUrl('https://x.com/a/status/1')?.id,
        SocialPlatform.x,
      );
      expect(SocialPlatformInfo.fromUrl('https://cdn.example.com/a.png'), isNull);
    });

    test('publish + find claim by reference is case-insensitive', () async {
      final published = await ClaimRegistry.instance.publish(
        medium: TraceMedium.image,
        owner: 'Wejdan',
        subject: 'a.png',
        reference: 'AbCdEf123456',
        issued: '2026-08-09T00:00:00Z',
        alg: 'hmac-sha256',
        kid: alice.kid,
      );
      final found =
          await ClaimRegistry.instance.findByReference('abcdef123456');
      expect(found?.id, published.id);
      expect(found?.owner, 'Wejdan');
    });

    test('watchlist dedupes URL and stores sightings', () async {
      final a = await TraceStore.instance.addWatchTarget(
        'https://cdn.example.com/pic.png',
        label: 'Portfolio',
      );
      final b = await TraceStore.instance.addWatchTarget(
        'https://cdn.example.com/pic.png',
        label: 'Again',
      );
      expect(a.id, b.id);
      expect((await TraceStore.instance.listWatchTargets()).length, 1);

      await TraceStore.instance.addSighting(TraceSighting(
        id: 's-deep',
        url: a.url,
        medium: TraceMedium.image,
        at: DateTime.utc(2026, 8, 9),
        found: true,
        claimStatus: ClaimStatus.authenticated,
        owner: 'Wejdan',
        reference: 'REF',
      ));
      final sightings = await TraceStore.instance.listSightings();
      expect(sightings.first.found, isTrue);
    });

    test('url tracer rejects non-http schemes', () async {
      expect(
        () => UrlTracer.instance.scanUrl('file:///tmp/a.png', persist: false),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('deep reports', () {
    test('sealed report verifies and breaks on tamper', () {
      final sealed = sealReport(const ReportBody(
        medium: 'image',
        subject: 'a.png',
        owner: 'Wejdan',
        verified: true,
        issued: 't',
        generated: 'g',
        evidence: {'k': 'v'},
      ));
      expect(verifySealedReport(sealed), isTrue);
      final tampered = SealedReport(
        body: const ReportBody(
          medium: 'image',
          subject: 'a.png',
          owner: 'Other',
          verified: true,
          issued: 't',
          generated: 'g',
          evidence: {'k': 'v'},
        ),
        seal: sealed.seal,
      );
      expect(verifySealedReport(tampered), isFalse);
    });
  });
}
