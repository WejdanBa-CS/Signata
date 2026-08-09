/// Auth session for Signata.
///
/// Email accounts are stored on-device (PBKDF2-hashed) so the login flow works
/// without a backend. Google Sign-In uses the platform SDK when configured.
///
/// Hardening:
/// - PBKDF2-HMAC-SHA256 password hashes (with migration from legacy SHA-256)
/// - Sessions kept in Flutter Secure Storage (not SharedPreferences)
/// - Password policy + failed-attempt lockout
/// - Neutral credential errors (no account enumeration)
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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

/// Password strength rules for on-device email accounts.
class PasswordPolicy {
  static const minLength = 10;

  /// Returns null when [password] is acceptable, otherwise a user-facing reason.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password)) {
      return 'Password must include at least one letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include at least one number.';
    }
    if (RegExp(r'^\s|\s$').hasMatch(password)) {
      return 'Password cannot start or end with a space.';
    }
    return null;
  }
}

/// Password hashing helpers (PBKDF2-HMAC-SHA256 + legacy SHA-256 verify).
class PasswordHasher {
  static const algoPbkdf2 = 'pbkdf2-sha256';
  static const algoLegacySha256 = 'sha256';
  static const iterations = 120000;
  static const keyBytes = 32;

  static String hash(String password, String saltBase64) {
    final salt = base64Url.decode(saltBase64);
    final derived = pbkdf2HmacSha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      keyLength: keyBytes,
    );
    return base64UrlEncode(derived);
  }

  static bool verify({
    required String password,
    required String saltBase64,
    required String expectedHash,
    required String algorithm,
  }) {
    final computed = algorithm == algoLegacySha256
        ? _legacySha256(password, saltBase64)
        : hash(password, saltBase64);
    return constantTimeEquals(computed, expectedHash);
  }

  static bool needsUpgrade(String algorithm) => algorithm != algoPbkdf2;

  static String _legacySha256(String password, String salt) =>
      sha256.convert(utf8.encode('$salt|$password')).toString();

  /// RFC 8018 PBKDF2 with HMAC-SHA256.
  static Uint8List pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    if (iterations < 1 || keyLength < 1) {
      throw ArgumentError('Invalid PBKDF2 parameters');
    }
    final hmac = Hmac(sha256, password);
    const hLen = 32;
    final blockCount = (keyLength + hLen - 1) ~/ hLen;
    final out = BytesBuilder(copy: false);

    for (var block = 1; block <= blockCount; block++) {
      final blockSalt = BytesBuilder(copy: false)
        ..add(salt)
        ..add([
          (block >> 24) & 0xff,
          (block >> 16) & 0xff,
          (block >> 8) & 0xff,
          block & 0xff,
        ]);
      var u = hmac.convert(blockSalt.toBytes()).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }

    return Uint8List.fromList(out.toBytes().sublist(0, keyLength));
  }

  static bool constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _sessionKey = 'signata_session_v2';
  static const _legacySessionKey = 'signata_session_v1';
  static const _usersKey = 'signata_users_v1';
  static const _lockoutKey = 'signata_lockout_v1';
  static const _maxFailedAttempts = 5;
  static const _lockoutBaseSeconds = 30;
  static const _genericCredentialError =
      'Incorrect email or password.';

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final _google = GoogleSignIn.instance;

  AuthUser? _user;
  bool _ready = false;
  bool _googleReady = false;

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isReady => _ready;

  bool get isGoogleConfigured => GoogleAuthConfig.hasServerClientId;

  Future<void> initialize() async {
    await GoogleAuthConfig.load();
    await _initGoogleSignIn();
    await _restoreSession();
    _ready = true;
    notifyListeners();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      // Android requires the *Web* OAuth client ID as serverClientId.
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
          'Google Sign-In: missing Web client ID. '
          'Paste it on the login screen, or set GOOGLE_SERVER_CLIENT_ID.',
        );
      }
    } catch (error) {
      debugPrint('Google Sign-In init skipped: $error');
      _googleReady = false;
    }
  }

  /// Saves a Google Web client ID and re-initializes the SDK.
  Future<void> configureGoogleServerClientId(String clientId) async {
    await GoogleAuthConfig.saveServerClientId(clientId);
    await _initGoogleSignIn();
    notifyListeners();
    if (!_googleReady) {
      throw const AuthException(
        'Google Sign-In still failed to initialize. Check the Web client ID.',
      );
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (password.isEmpty) {
      throw const AuthException('Enter your password.');
    }

    await _assertNotLockedOut(normalized);

    final users = await _loadUsers();
    final record = users[normalized];
    if (record == null) {
      await _registerFailedAttempt(normalized);
      throw const AuthException(_genericCredentialError);
    }

    final algo = (record['algo'] as String?) ?? PasswordHasher.algoLegacySha256;
    final ok = PasswordHasher.verify(
      password: password,
      saltBase64: record['salt'] as String,
      expectedHash: record['hash'] as String,
      algorithm: algo,
    );
    if (!ok) {
      await _registerFailedAttempt(normalized);
      throw const AuthException(_genericCredentialError);
    }

    await _clearFailedAttempts(normalized);

    // Upgrade legacy hashes on successful sign-in.
    if (PasswordHasher.needsUpgrade(algo)) {
      final salt = _randomSalt();
      users[normalized] = {
        ...record,
        'salt': salt,
        'algo': PasswordHasher.algoPbkdf2,
        'hash': PasswordHasher.hash(password, salt),
        'iterations': PasswordHasher.iterations,
      };
      await _saveUsers(users);
    }

    await _setSession(AuthUser(
      id: record['id'] as String,
      email: normalized,
      displayName:
          record['displayName'] as String? ?? normalized.split('@').first,
      provider: AuthProvider.email,
    ));
  }

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    String? confirmPassword,
  }) async {
    final normalized = email.trim().toLowerCase();
    final display =
        name.trim().isEmpty ? normalized.split('@').first : name.trim();
    if (!_isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) {
      throw AuthException(policyError);
    }
    if (confirmPassword != null && confirmPassword != password) {
      throw const AuthException('Passwords do not match.');
    }

    await _assertNotLockedOut(normalized);

    final users = await _loadUsers();
    if (users.containsKey(normalized)) {
      // Same generic wording as sign-in to avoid confirming email existence.
      throw const AuthException(
        'Could not create that account. Try signing in, or use a different email.',
      );
    }

    final salt = _randomSalt();
    final id = 'email_${_randomId()}';
    users[normalized] = {
      'id': id,
      'displayName': display,
      'salt': salt,
      'algo': PasswordHasher.algoPbkdf2,
      'iterations': PasswordHasher.iterations,
      'hash': PasswordHasher.hash(password, salt),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _saveUsers(users);
    await _clearFailedAttempts(normalized);

    await _setSession(AuthUser(
      id: id,
      email: normalized,
      displayName: display,
      provider: AuthProvider.email,
    ));
  }

  Future<void> signInWithGoogle() async {
    if (!GoogleAuthConfig.hasServerClientId) {
      throw const AuthException(
        'Google setup needed. Tap “Set up Google Sign-In”, paste your Web '
        'client ID, and make sure an Android OAuth client exists for '
        'package app.signata.signata.',
      );
    }
    if (!_googleReady) {
      await _initGoogleSignIn();
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
    await _secure.delete(key: _sessionKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacySessionKey);
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    // Prefer encrypted session; migrate any leftover SharedPreferences session.
    String? raw = await _secure.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_legacySessionKey);
      if (raw != null) {
        try {
          final user =
              AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          await _setSession(user);
          await prefs.remove(_legacySessionKey);
          return;
        } catch (_) {
          await prefs.remove(_legacySessionKey);
          raw = null;
        }
      }
    }
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // Reject tampered / incomplete session blobs.
      if (decoded['token'] is! String ||
          (decoded['token'] as String).length < 16) {
        await _secure.delete(key: _sessionKey);
        return;
      }
      final userJson = decoded['user'];
      if (userJson is! Map) {
        await _secure.delete(key: _sessionKey);
        return;
      }
      _user = AuthUser.fromJson(Map<String, dynamic>.from(userJson));
    } catch (_) {
      await _secure.delete(key: _sessionKey);
    }
  }

  Future<void> _setSession(AuthUser user) async {
    _user = user;
    final token = _randomSalt();
    final payload = jsonEncode({
      'token': token,
      'issuedAt': DateTime.now().toUtc().toIso8601String(),
      'user': user.toJson(),
    });
    await _secure.write(key: _sessionKey, value: payload);

    // Ensure legacy plaintext session is gone.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacySessionKey);
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

  Future<Map<String, dynamic>> _loadLockout() async {
    final raw = await _secure.read(key: _lockoutKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveLockout(Map<String, dynamic> data) async {
    await _secure.write(key: _lockoutKey, value: jsonEncode(data));
  }

  Future<void> _assertNotLockedOut(String email) async {
    final data = await _loadLockout();
    final entry = data[email];
    if (entry is! Map) return;
    final untilMs = entry['until'] as int?;
    if (untilMs == null) return;
    final remaining =
        DateTime.fromMillisecondsSinceEpoch(untilMs).difference(DateTime.now());
    if (remaining.isNegative) return;
    final seconds = remaining.inSeconds + 1;
    throw AuthException(
      'Too many failed attempts. Try again in ${seconds}s.',
    );
  }

  Future<void> _registerFailedAttempt(String email) async {
    final data = await _loadLockout();
    final entry = Map<String, dynamic>.from(
      (data[email] as Map?) ?? const <String, dynamic>{},
    );
    final attempts = ((entry['attempts'] as int?) ?? 0) + 1;
    entry['attempts'] = attempts;
    if (attempts >= _maxFailedAttempts) {
      final streak = (attempts - _maxFailedAttempts) + 1;
      final seconds = _lockoutBaseSeconds * (1 << (streak - 1).clamp(0, 4));
      entry['until'] =
          DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
    }
    data[email] = entry;
    await _saveLockout(data);
  }

  Future<void> _clearFailedAttempts(String email) async {
    final data = await _loadLockout();
    if (!data.containsKey(email)) return;
    data.remove(email);
    await _saveLockout(data);
  }

  static bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  static String _randomSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _randomId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(12, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
