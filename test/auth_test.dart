import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signata/core/auth.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects short passwords', () {
      expect(PasswordPolicy.validate('Ab1'), isNotNull);
      expect(PasswordPolicy.validate('Abcdefg1'), isNotNull);
    });

    test('requires letter and number', () {
      expect(PasswordPolicy.validate('abcdefghij'), isNotNull);
      expect(PasswordPolicy.validate('1234567890'), isNotNull);
    });

    test('accepts strong enough passwords', () {
      expect(PasswordPolicy.validate('Correct1horse'), isNull);
      expect(PasswordPolicy.validate('signata2026X'), isNull);
    });
  });

  group('PasswordHasher', () {
    test('PBKDF2 is deterministic for same inputs', () {
      final salt = base64UrlEncode(List<int>.generate(16, (i) => i + 1));
      final a = PasswordHasher.hash('Correct1horse', salt);
      final b = PasswordHasher.hash('Correct1horse', salt);
      expect(a, b);
      expect(a, isNot(equals(PasswordHasher.hash('Correct1horsf', salt))));
    });

    test('verify accepts matching PBKDF2 hash', () {
      final salt = base64UrlEncode(List<int>.generate(16, (i) => i + 3));
      final hash = PasswordHasher.hash('SecurePass9', salt);
      expect(
        PasswordHasher.verify(
          password: 'SecurePass9',
          saltBase64: salt,
          expectedHash: hash,
          algorithm: PasswordHasher.algoPbkdf2,
        ),
        isTrue,
      );
      expect(
        PasswordHasher.verify(
          password: 'wrong-password',
          saltBase64: salt,
          expectedHash: hash,
          algorithm: PasswordHasher.algoPbkdf2,
        ),
        isFalse,
      );
    });

    test('verify still accepts legacy SHA-256 hashes', () {
      const salt = 'legacy-salt';
      const password = 'OldPass12ab';
      final expected =
          sha256.convert(utf8.encode('$salt|$password')).toString();
      expect(
        PasswordHasher.verify(
          password: password,
          saltBase64: salt,
          expectedHash: expected,
          algorithm: PasswordHasher.algoLegacySha256,
        ),
        isTrue,
      );
      expect(
        PasswordHasher.needsUpgrade(PasswordHasher.algoLegacySha256),
        isTrue,
      );
      expect(
        PasswordHasher.needsUpgrade(PasswordHasher.algoPbkdf2),
        isFalse,
      );
    });

    test('constantTimeEquals is length-sensitive', () {
      expect(PasswordHasher.constantTimeEquals('abc', 'abc'), isTrue);
      expect(PasswordHasher.constantTimeEquals('abc', 'abd'), isFalse);
      expect(PasswordHasher.constantTimeEquals('abc', 'ab'), isFalse);
    });

    test('pbkdf2 produces expected key length', () {
      final key = PasswordHasher.pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1000,
        keyLength: 32,
      );
      expect(key.length, 32);
    });
  });
}
