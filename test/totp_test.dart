import 'package:flutter_test/flutter_test.dart';
import 'package:signata/core/totp.dart';

void main() {
  group('Totp', () {
    test('round-trips Base32', () {
      final secret = Totp.generateSecret();
      expect(secret, isNotEmpty);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue);
      final raw = Totp.decodeBase32(secret);
      expect(Totp.encodeBase32(raw), secret);
    });

    test('verifies current code and rejects wrong code', () {
      final secret = Totp.generateSecret();
      final code = Totp.codeAt(secret);
      expect(code.length, 6);
      expect(Totp.verify(secret, code), isTrue);
      expect(Totp.verify(secret, '000000'), isFalse);
    });

    test('otpauth URI includes issuer and secret', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final uri = Totp.otpauthUri(secret: secret, accountName: 'you@example.com');
      expect(uri.startsWith('otpauth://totp/'), isTrue);
      expect(uri.contains('secret=$secret'), isTrue);
      expect(uri.contains('Signata'), isTrue);
    });

    test('known RFC vector-style code is stable for fixed time', () {
      // Secret "Hello!" -> JBSWY3DPEHPK3PXP in many examples; check determinism.
      const secret = 'JBSWY3DPEHPK3PXP';
      final at = DateTime.utc(2020, 1, 1, 0, 0, 0);
      final a = Totp.codeAt(secret, at: at);
      final b = Totp.codeAt(secret, at: at);
      expect(a, b);
      expect(Totp.verify(secret, a, at: at), isTrue);
    });
  });
}
