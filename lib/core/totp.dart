/// RFC 6238 TOTP helpers for on-device two-factor auth.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class Totp {
  Totp._();

  static const digits = 6;
  static const periodSeconds = 30;
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Cryptographically random 20-byte secret, Base32-encoded (no padding).
  static String generateSecret({int bytes = 20}) {
    final random = Random.secure();
    final raw = Uint8List.fromList(
      List<int>.generate(bytes, (_) => random.nextInt(256)),
    );
    return encodeBase32(raw);
  }

  static String otpauthUri({
    required String secret,
    required String accountName,
    String issuer = 'Signata',
  }) {
    final label = Uri.encodeComponent('$issuer:$accountName');
    final query = {
      'secret': secret,
      'issuer': issuer,
      'algorithm': 'SHA1',
      'digits': '$digits',
      'period': '$periodSeconds',
    }.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return 'otpauth://totp/$label?$query';
  }

  static String codeAt(String secretBase32, {DateTime? at}) {
    final key = decodeBase32(secretBase32);
    final seconds =
        (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
    final counter = seconds ~/ periodSeconds;
    return _hotp(key, counter);
  }

  /// Accepts the current window ±1 to tolerate slight clock skew.
  static bool verify(
    String secretBase32,
    String code, {
    DateTime? at,
    int window = 1,
  }) {
    final cleaned = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      return false;
    }
    final key = decodeBase32(secretBase32);
    final seconds =
        (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
    final counter = seconds ~/ periodSeconds;
    for (var i = -window; i <= window; i++) {
      if (_constantTimeEquals(_hotp(key, counter + i), cleaned)) return true;
    }
    return false;
  }

  static String _hotp(Uint8List key, int counter) {
    final data = ByteData(8)..setUint64(0, counter);
    final digest = Hmac(sha1, key).convert(data.buffer.asUint8List()).bytes;
    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    final otp = binary % pow(10, digits).toInt();
    return otp.toString().padLeft(digits, '0');
  }

  static String encodeBase32(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bitsLeft = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        out.write(_alphabet[(buffer >> (bitsLeft - 5)) & 31]);
        bitsLeft -= 5;
      }
    }
    if (bitsLeft > 0) {
      out.write(_alphabet[(buffer << (5 - bitsLeft)) & 31]);
    }
    return out.toString();
  }

  static Uint8List decodeBase32(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s=]'), '').toUpperCase();
    var buffer = 0;
    var bitsLeft = 0;
    final out = BytesBuilder(copy: false);
    for (final ch in cleaned.codeUnits) {
      final idx = _alphabet.codeUnits.indexOf(ch);
      if (idx < 0) {
        throw FormatException('Invalid Base32 character');
      }
      buffer = (buffer << 5) | idx;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        out.addByte((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }
    return out.toBytes();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
