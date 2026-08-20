/// OWASP-oriented URL guards for Trace and optional claim registry.
library;

/// Result of validating a user-supplied http(s) URL.
class SafeUrlResult {
  const SafeUrlResult.ok(this.uri) : error = null;
  const SafeUrlResult.err(this.error) : uri = null;

  final Uri? uri;
  final String? error;

  bool get isOk => uri != null;
}

/// Blocks private networks, metadata endpoints, and non-http(s) schemes (SSRF).
class SafeUrl {
  SafeUrl._();

  static const blockedHostnames = {
    'localhost',
    'localhost.localdomain',
    'metadata.google.internal',
  };

  /// Public http(s) URL suitable for Trace downloads.
  static SafeUrlResult parseTraceUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const SafeUrlResult.err('Enter a URL.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return const SafeUrlResult.err('Enter a valid http(s) URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const SafeUrlResult.err('Only http and https URLs are allowed.');
    }
    if (uri.userInfo.isNotEmpty) {
      return const SafeUrlResult.err('URLs with embedded credentials are not allowed.');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return const SafeUrlResult.err('Enter a valid http(s) URL.');
    }
    if (blockedHostnames.contains(host) || host.endsWith('.local')) {
      return const SafeUrlResult.err('That URL points to a private or local host.');
    }
    if (_isPrivateOrReservedHost(host)) {
      return const SafeUrlResult.err('Private or internal network URLs are not allowed.');
    }
    return SafeUrlResult.ok(uri);
  }

  /// Remote registry base must be https and not point at private networks.
  static SafeUrlResult parseRegistryBase(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      return const SafeUrlResult.err('Registry URL is empty.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return const SafeUrlResult.err('Enter a valid registry URL.');
    }
    if (uri.scheme != 'https') {
      return const SafeUrlResult.err('Registry URL must use https.');
    }
    if (uri.userInfo.isNotEmpty) {
      return const SafeUrlResult.err('Registry URL cannot include credentials.');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return const SafeUrlResult.err('Enter a valid registry URL.');
    }
    if (blockedHostnames.contains(host) || host.endsWith('.local')) {
      return const SafeUrlResult.err('Registry URL cannot point to a local host.');
    }
    if (_isPrivateOrReservedHost(host)) {
      return const SafeUrlResult.err('Registry URL cannot point to a private network.');
    }
    return SafeUrlResult.ok(uri);
  }

  static bool _isPrivateOrReservedHost(String host) {
    if (host == '::1' || host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd')) {
      return true;
    }
    final ip = _parseIpv4(host);
    if (ip == null) return false;
    final a = ip[0];
    final b = ip[1];
    if (a == 127) return true;
    if (a == 10) return true;
    if (a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT
    return false;
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
      out.add(n);
    }
    return out;
  }
}

/// Simple in-process rate limiter for Trace scans (per device session).
class TraceRateLimiter {
  TraceRateLimiter._();

  static final TraceRateLimiter instance = TraceRateLimiter._();

  static const maxScansPerHour = 40;
  static const window = Duration(hours: 1);

  final List<DateTime> _events = [];

  bool allow() {
    final now = DateTime.now().toUtc();
    _events.removeWhere((t) => now.difference(t) > window);
    if (_events.length >= maxScansPerHour) return false;
    _events.add(now);
    return true;
  }

  void resetForTests() => _events.clear();
}
