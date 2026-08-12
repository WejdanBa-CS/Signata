import 'package:flutter_test/flutter_test.dart';
import 'package:signata/core/local_data.dart';

void main() {
  test('parses claim key from recovery kit text', () {
    const kit = '''
Signata recovery kit
====================
Email: you@example.com
Account id: email_abc

Claim key (base64url) — required to prove old fingerprints as "yours":
ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-ab

Keep this file offline.
''';
    expect(
      parseClaimKeyFromRecoveryText(kit),
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-ab',
    );
  });

  test('parses bare claim key', () {
    const key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-abcd';
    expect(parseClaimKeyFromRecoveryText(key), key);
  });

  test('rejects empty junk', () {
    expect(parseClaimKeyFromRecoveryText('hello'), isNull);
  });
}
