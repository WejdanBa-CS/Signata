/// Google OAuth client IDs for Sign-In.
///
/// Create these in Google Cloud Console (APIs & Services → Credentials):
/// 1. OAuth client type **Web application** → use its ID as [serverClientId]
/// 2. OAuth client type **Android** with package `app.signata.signata` + SHA-1
///    (needed for Google to trust this app; you usually do NOT paste that ID here)
///
/// Sources (first match wins):
/// 1. Runtime override saved from the login screen (secure storage)
/// 2. `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` or `--dart-define-from-file=`
/// 3. Optional [defaultValue] below
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const _storageKey = 'signata_google_server_client_id';

  /// Debug Android package + SHA-1 for the OAuth Android client.
  static const androidPackageName = 'app.signata.signata';
  static const androidDebugSha1 =
      '0A:3A:67:69:E8:44:A7:A5:0A:1B:FD:CD:61:A1:32:5C:2B:F6:9F:AA';

  /// Web client ID — required on Android as `serverClientId`.
  static const String _defineServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Optional. Mostly used on iOS/Web. On Android, leave empty unless you have
  /// a reason to override the default client.
  static const String clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static String? _runtimeServerClientId;
  static bool _loaded = false;

  static final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static String get serverClientId {
    final runtime = _runtimeServerClientId?.trim() ?? '';
    if (runtime.isNotEmpty) return runtime;
    return _defineServerClientId.trim();
  }

  static bool get hasServerClientId => serverClientId.isNotEmpty;

  static bool get isLikelyClientId =>
      RegExp(r'^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$')
          .hasMatch(serverClientId);

  /// Loads any previously saved Web client ID from secure storage.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      _runtimeServerClientId = await _secure.read(key: _storageKey);
    } catch (_) {
      _runtimeServerClientId = null;
    }
    _loaded = true;
  }

  /// Saves a Web client ID so Google Sign-In works without rebuilding.
  static Future<void> saveServerClientId(String value) async {
    final trimmed = value.trim();
    if (!_looksLikeClientId(trimmed)) {
      throw ArgumentError(
        'Paste the Web client ID (…apps.googleusercontent.com).',
      );
    }
    _runtimeServerClientId = trimmed;
    _loaded = true;
    await _secure.write(key: _storageKey, value: trimmed);
  }

  static Future<void> clearServerClientId() async {
    _runtimeServerClientId = null;
    await _secure.delete(key: _storageKey);
  }

  static bool _looksLikeClientId(String value) =>
      RegExp(r'^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$')
          .hasMatch(value);
}
