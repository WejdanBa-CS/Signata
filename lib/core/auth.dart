/// Auth session for EchoMark.
///
/// Email accounts are stored on-device (hashed) so the login flow works without
/// a backend. Google Sign-In uses the platform SDK when configured.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth_config.dart';

enum AuthProvider { email, google }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.provider,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String displayName;
  final AuthProvider provider;
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'provider': provider.name,
        'photoUrl': photoUrl,
      };

  static AuthUser fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        provider: AuthProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => AuthProvider.email,
        ),
        photoUrl: json['photoUrl'] as String?,
      );
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _sessionKey = 'em_session_v1';
  static const _usersKey = 'em_users_v1';

  final _secure = const FlutterSecureStorage();
  final _google = GoogleSignIn.instance;

  AuthUser? _user;
  bool _ready = false;
  bool _googleReady = false;

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isReady => _ready;

  Future<void> initialize() async {
    try {
      // Android requires the *Web* OAuth client ID as serverClientId.
      // Create it in Google Cloud Console → APIs & Services → Credentials.
      await _google.initialize(
        clientId: GoogleAuthConfig.clientId.isEmpty
            ? null
            : GoogleAuthConfig.clientId,
        serverClientId: GoogleAuthConfig.serverClientId.isEmpty
            ? null
            : GoogleAuthConfig.serverClientId,
      );
      _googleReady = GoogleAuthConfig.hasServerClientId;
      if (!_googleReady) {
        debugPrint(
          'Google Sign-In: set GOOGLE_SERVER_CLIENT_ID (Web client ID) '
          'via --dart-define or lib/core/google_auth_config.dart',
        );
      }
    } catch (error) {
      debugPrint('Google Sign-In init skipped: $error');
      _googleReady = false;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        await prefs.remove(_sessionKey);
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }

    final users = await _loadUsers();
    final record = users[normalized];
    if (record == null) {
      throw const AuthException('No account found for that email. Create one?');
    }
    final hash = _hashPassword(password, record['salt'] as String);
    if (hash != record['hash']) {
      throw const AuthException('Incorrect password.');
    }

    await _setSession(AuthUser(
      id: record['id'] as String,
      email: normalized,
      displayName: record['displayName'] as String? ?? normalized.split('@').first,
      provider: AuthProvider.email,
    ));
  }

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final display = name.trim().isEmpty
        ? normalized.split('@').first
        : name.trim();
    if (!_isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }

    final users = await _loadUsers();
    if (users.containsKey(normalized)) {
      throw const AuthException('An account already exists for that email.');
    }

    final salt = _randomSalt();
    users[normalized] = {
      'id': 'email_${DateTime.now().millisecondsSinceEpoch}',
      'displayName': display,
      'salt': salt,
      'hash': _hashPassword(password, salt),
    };
    await _saveUsers(users);

    await _setSession(AuthUser(
      id: users[normalized]!['id'] as String,
      email: normalized,
      displayName: display,
      provider: AuthProvider.email,
    ));
  }

  Future<void> signInWithGoogle() async {
    if (!GoogleAuthConfig.hasServerClientId) {
      throw const AuthException(
        'Google Client IDs are missing. Add your Web OAuth client ID as '
        'GOOGLE_SERVER_CLIENT_ID (see lib/core/google_auth_config.dart), '
        'and register an Android OAuth client with package '
        'app.echomark.echomark + your SHA-1.',
      );
    }
    if (!_googleReady) {
      throw const AuthException(
        'Google Sign-In is not available on this device yet. Use email instead, or configure a Google OAuth client for the app.',
      );
    }
    try {
      if (!_google.supportsAuthenticate()) {
        throw const AuthException(
          'Google Sign-In is not supported on this platform. Use email instead.',
        );
      }
      final account = await _google.authenticate();
      await _setSession(AuthUser(
        id: 'google_${account.id}',
        email: account.email,
        displayName: account.displayName?.trim().isNotEmpty == true
            ? account.displayName!.trim()
            : account.email.split('@').first,
        provider: AuthProvider.google,
        photoUrl: account.photoUrl,
      ));
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Google sign-in was cancelled.');
      }
      throw AuthException(
        'Google sign-in failed. Use email for now, or add a Google OAuth client ID for this app. (${error.description ?? error.code.name})',
      );
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(
        'Google sign-in failed. Use email for now. ($error)',
      );
    }
  }

  Future<void> signOut() async {
    try {
      if (_googleReady) await _google.signOut();
    } catch (_) {}
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    notifyListeners();
  }

  Future<void> _setSession(AuthUser user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsers() async {
    final raw = await _secure.read(key: _usersKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          Map<String, dynamic>.from(value as Map),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, Map<String, dynamic>> users) async {
    await _secure.write(key: _usersKey, value: jsonEncode(users));
  }

  static bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  static String _randomSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hashPassword(String password, String salt) =>
      sha256.convert(utf8.encode('$salt|$password')).toString();
}
