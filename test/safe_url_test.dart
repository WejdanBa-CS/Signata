import 'package:flutter_test/flutter_test.dart';
import 'package:signata/core/claim_registry.dart';
import 'package:signata/core/safe_url.dart';

void main() {
  group('SafeUrl.parseTraceUrl', () {
    test('accepts public https URLs', () {
      final result = SafeUrl.parseTraceUrl('https://cdn.example.com/a.png');
      expect(result.isOk, isTrue);
      expect(result.uri!.host, 'cdn.example.com');
    });

    test('rejects ftp and file schemes', () {
      expect(SafeUrl.parseTraceUrl('ftp://x/y.png').isOk, isFalse);
      expect(SafeUrl.parseTraceUrl('file:///etc/passwd').isOk, isFalse);
    });

    test('rejects localhost and private IPs', () {
      expect(SafeUrl.parseTraceUrl('http://127.0.0.1/x').isOk, isFalse);
      expect(SafeUrl.parseTraceUrl('http://localhost/x').isOk, isFalse);
      expect(SafeUrl.parseTraceUrl('http://192.168.1.1/x').isOk, isFalse);
      expect(SafeUrl.parseTraceUrl('http://10.0.0.1/x').isOk, isFalse);
      expect(SafeUrl.parseTraceUrl('http://169.254.169.254/').isOk, isFalse);
    });

    test('rejects URLs with embedded credentials', () {
      expect(
        SafeUrl.parseTraceUrl('https://user:pass@example.com/x').isOk,
        isFalse,
      );
    });
  });

  group('SafeUrl.parseRegistryBase', () {
    test('accepts public https registry', () {
      final result = SafeUrl.parseRegistryBase('https://registry.example.com');
      expect(result.isOk, isTrue);
    });

    test('rejects http and private hosts', () {
      expect(SafeUrl.parseRegistryBase('http://registry.example.com').isOk, isFalse);
      expect(SafeUrl.parseRegistryBase('https://127.0.0.1').isOk, isFalse);
    });
  });

  group('ClaimRegistry.configure', () {
    test('ignores invalid registry URLs', () {
      ClaimRegistry.configure(remoteBaseUrl: 'https://127.0.0.1');
      expect(ClaimRegistry.hasRemote, isFalse);
      ClaimRegistry.configure(remoteBaseUrl: 'https://registry.example.com');
      expect(ClaimRegistry.hasRemote, isTrue);
      ClaimRegistry.configure(remoteBaseUrl: '');
    });
  });

  group('TraceRateLimiter', () {
    test('allows scans under the hourly cap', () {
      TraceRateLimiter.instance.resetForTests();
      for (var i = 0; i < TraceRateLimiter.maxScansPerHour; i++) {
        expect(TraceRateLimiter.instance.allow(), isTrue);
      }
      expect(TraceRateLimiter.instance.allow(), isFalse);
      TraceRateLimiter.instance.resetForTests();
    });
  });
}
