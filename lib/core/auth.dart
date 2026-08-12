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
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_auth_config.dart';
import 'local_data.dart';
import 'secure_store.dart';
import 'totp.dart';

enum AuthProvider { email, google }

/// Thrown when password was accepted but a TOTP code is still required.
class TotpRequiredException implements Exception {
  const TotpRequiredException();
  @override
  String toString() => 'Authenticator code required.';
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.provider,
    this.photoUrl,
    this.totpEnabled = false,
    this.emailVerified = true,
  });

  final String id;
  final String email;
  final String displayName;
  final AuthProvider provider;
  final String? photoUrl;
  final bool totpEnabled;
  final bool emailVerified;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'provider': provider.name,
        'photoUrl': photoUrl,
        'totpEnabled': totpEnabled,
        'emailVerified': emailVerified,
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
        totpEnabled: json['totpEnabled'] == true,
        // Missing key → already verified (pre-verification installs).
        emailVerified: json.containsKey('emailVerified')
            ? json['emailVerified'] == true
            : true,
      );

  AuthUser copyWith({bool? totpEnabled, bool? emailVerified}) => AuthUser(
        id: id,
        email: email,
        displayName: displayName,
        provider: provider,
        photoUrl: photoUrl,
        totpEnabled: totpEnabled ?? this.totpEnabled,
        emailVerified: emailVerified ?? this.emailVerified,
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

  static const _common = {
    'password',
    'password1',
    'password123',
    '1234567890',
    'qwerty1234',
    'letmein123',
    'admin12345',
    'welcome123',
    'signata123',
    'iloveyou12',
  };

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
    if (_common.contains(password.toLowerCase())) {
      return 'Choose a less common password.';
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

  final _secure = signataSecureStorage;
  final _google = GoogleSignIn.instance;

  AuthUser? _user;
  bool _ready = false;
  bool _googleReady = false;
  final _secureRandom = Random.secure();

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
          'Set GOOGLE_SERVER_CLIENT_ID via --dart-define / google_oauth.env.',
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
    String? totpCode,
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

    final totpEnabled = record['totpEnabled'] == true;
    final totpSecret = await _readTotpSecret(normalized, record);
    if (totpEnabled && totpSecret != null && totpSecret.isNotEmpty) {
      final code = totpCode?.trim() ?? '';
      if (code.isEmpty) {
        throw const TotpRequiredException();
      }
      if (!Totp.verify(totpSecret, code)) {
        await _registerFailedAttempt(normalized);
        throw const AuthException('Incorrect authenticator code.');
      }
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
      totpEnabled: totpEnabled,
      emailVerified: record.containsKey('emailVerified')
          ? record['emailVerified'] == true
          : true,
    ));
  }

  /// Starts 2FA enrollment; returns secret + otpauth URI. Confirm with [confirmTotpSetup].
  Future<({String secret, String otpauth})> beginTotpSetup() async {
    final user = _user;
    if (user == null || user.provider != AuthProvider.email) {
      throw const AuthException('2FA is available for email accounts only.');
    }
    final secret = Totp.generateSecret();
    final otpauth = Totp.otpauthUri(secret: secret, accountName: user.email);
    await _secure.write(key: _pendingTotpKey(user.email), value: secret);
    return (secret: secret, otpauth: otpauth);
  }

  Future<void> confirmTotpSetup(String code) async {
    final user = _user;
    if (user == null || user.provider != AuthProvider.email) {
      throw const AuthException('2FA is available for email accounts only.');
    }
    final secret = await _secure.read(key: _pendingTotpKey(user.email));
    if (secret == null || secret.isEmpty) {
      throw const AuthException('Start 2FA setup again.');
    }
    if (!Totp.verify(secret, code)) {
      throw const AuthException('Incorrect authenticator code. Try again.');
    }
    final users = await _loadUsers();
    final record = users[user.email];
    if (record == null) {
      throw const AuthException('Account not found.');
    }
    users[user.email] = {
      ...record,
      'totpEnabled': true,
    };
    await _saveUsers(users);
    await _secure.write(key: _totpSecretKey(user.email), value: secret);
    await _secure.delete(key: _pendingTotpKey(user.email));
    await _setSession(user.copyWith(totpEnabled: true));
  }

  Future<void> disableTotp({
    required String password,
    required String totpCode,
  }) async {
    final user = _user;
    if (user == null || user.provider != AuthProvider.email) {
      throw const AuthException('2FA is available for email accounts only.');
    }
    final users = await _loadUsers();
    final record = users[user.email];
    if (record == null) {
      throw const AuthException('Account not found.');
    }
    final algo = (record['algo'] as String?) ?? PasswordHasher.algoLegacySha256;
    final passwordOk = PasswordHasher.verify(
      password: password,
      saltBase64: record['salt'] as String,
      expectedHash: record['hash'] as String,
      algorithm: algo,
    );
    if (!passwordOk) {
      throw const AuthException('Incorrect password.');
    }
    final secret = await _readTotpSecret(user.email, record);
    if (secret == null || !Totp.verify(secret, totpCode)) {
      throw const AuthException('Incorrect authenticator code.');
    }
    final updated = Map<String, dynamic>.from(record)
      ..['totpEnabled'] = false
      ..remove('totpSecret');
    users[user.email] = updated;
    await _saveUsers(users);
    await _secure.delete(key: _totpSecretKey(user.email));
    await _secure.delete(key: _pendingTotpKey(user.email));
    await _setSession(user.copyWith(totpEnabled: false));
  }

  String _pendingTotpKey(String email) =>
      'signata_totp_pending_${email.toLowerCase()}';

  String _totpSecretKey(String email) =>
      'signata_totp_secret_${email.toLowerCase()}';

  Future<String?> _readTotpSecret(
    String email,
    Map<String, dynamic> record,
  ) async {
    final isolated = await _secure.read(key: _totpSecretKey(email));
    if (isolated != null && isolated.isNotEmpty) return isolated;
    // Migrate secrets that were previously stored inside the users blob.
    final legacy = record['totpSecret'] as String?;
    if (legacy == null || legacy.isEmpty) return null;
    await _secure.write(key: _totpSecretKey(email), value: legacy);
    final cleaned = Map<String, dynamic>.from(record)..remove('totpSecret');
    final users = await _loadUsers();
    users[email] = cleaned;
    await _saveUsers(users);
    return legacy;
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
      'emailVerified': false,
    };
    await _saveUsers(users);
    await _clearFailedAttempts(normalized);

    await _setSession(AuthUser(
      id: id,
      email: normalized,
      displayName: display,
      provider: AuthProvider.email,
      emailVerified: false,
    ));
    await sendEmailVerification();
  }

  /// Creates a local activation code and optionally opens a mailto draft so the
  /// user can save it. Signata does not operate a mail server — this proves
  /// the user can access a mail app / copy the on-device code, not remote
  /// ownership of the inbox.
  ///
  /// Returns the plaintext code so the UI can show it if mailto fails.
  Future<String> sendEmailVerification() async {
    final user = _user;
    if (user == null || user.provider != AuthProvider.email) {
      throw const AuthException('Email activation is for email accounts.');
    }
    if (user.emailVerified) return '';

    final now = DateTime.now().toUtc();
    final raw = await _secure.read(key: _emailVerifyMetaKey(user.email));
    if (raw != null) {
      try {
        final meta = jsonDecode(raw) as Map<String, dynamic>;
        final lastMs = meta['sentAt'] as int?;
        if (lastMs != null) {
          final elapsed =
              now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true));
          if (elapsed.inSeconds < 45) {
            throw AuthException(
              'Wait ${45 - elapsed.inSeconds}s before requesting a new code.',
            );
          }
        }
      } catch (error) {
        if (error is AuthException) rethrow;
      }
    }

    final code =
        List.generate(6, (_) => _secureRandom.nextInt(10)).join();
    final salt = _randomSalt();
    final hash = sha256.convert(utf8.encode('$salt|$code')).toString();
    final expires = now.add(const Duration(minutes: 15));
    await _secure.write(
      key: _emailVerifyKey(user.email),
      value: jsonEncode({
        'salt': salt,
        'hash': hash,
        'expires': expires.millisecondsSinceEpoch,
      }),
    );
    await _secure.write(
      key: _emailVerifyMetaKey(user.email),
      value: jsonEncode({'sentAt': now.millisecondsSinceEpoch}),
    );

    final mailUri = Uri(
      scheme: 'mailto',
      path: user.email,
      query: _encodeMailQuery(
        subject: 'Signata account activation code',
        body:
            'Your Signata activation code is: $code\n\n'
            'This code was generated on your device (Signata does not send email). '
            'It expires in 15 minutes.\n'
            'Keep this code private.',
      ),
    );
    try {
      await launchUrl(mailUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // UI can display the returned code when mailto is unavailable.
    }
    if (kDebugMode) {
      debugPrint('Signata activation code for ${user.email}: $code');
    }
    return code;
  }

  Future<void> confirmEmailVerification(String code) async {
    final user = _user;
    if (user == null || user.provider != AuthProvider.email) {
      throw const AuthException('Email activation is for email accounts.');
    }
    await _assertNotLockedOut(user.email);
    final cleaned = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      throw const AuthException('Enter the 6-digit activation code.');
    }

    final raw = await _secure.read(key: _emailVerifyKey(user.email));
    if (raw == null || raw.isEmpty) {
      throw const AuthException('Request a new activation code.');
    }
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final expiresMs = payload['expires'] as int?;
    if (expiresMs == null ||
        DateTime.now().toUtc().isAfter(
              DateTime.fromMillisecondsSinceEpoch(expiresMs, isUtc: true),
            )) {
      await _secure.delete(key: _emailVerifyKey(user.email));
      throw const AuthException('That code expired. Tap Resend for a new one.');
    }
    final salt = payload['salt'] as String? ?? '';
    final expected = payload['hash'] as String? ?? '';
    final computed = sha256.convert(utf8.encode('$salt|$cleaned')).toString();
    if (!PasswordHasher.constantTimeEquals(computed, expected)) {
      await _registerFailedAttempt(user.email);
      throw const AuthException('Incorrect activation code.');
    }

    final users = await _loadUsers();
    final record = users[user.email];
    if (record == null) {
      throw const AuthException('Account not found.');
    }
    users[user.email] = {...record, 'emailVerified': true};
    await _saveUsers(users);
    await _secure.delete(key: _emailVerifyKey(user.email));
    await _secure.delete(key: _emailVerifyMetaKey(user.email));
    await _clearFailedAttempts(user.email);
    await _setSession(user.copyWith(emailVerified: true));
  }

  String _emailVerifyKey(String email) =>
      'signata_email_verify_${email.toLowerCase()}';

  String _emailVerifyMetaKey(String email) =>
      'signata_email_verify_meta_${email.toLowerCase()}';

  String _encodeMailQuery({required String subject, required String body}) {
    // mailto query must be encoded manually for broad client support.
    return 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  }

  Future<void> signInWithGoogle() async {
    if (!GoogleAuthConfig.hasServerClientId) {
      throw const AuthException(
        'Google Sign-In is not configured for this build. Use email instead.',
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
        'Google sign-in failed. Try again, or use email instead. '
        '(${error.description ?? error.code.name})',
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

  /// Deletes this on-device account and erases local Signata data for it.
  Future<void> deleteAccount({
    required String password,
    String? totpCode,
  }) async {
    final user = _user;
    if (user == null) {
      throw const AuthException('Not signed in.');
    }

    if (user.provider == AuthProvider.email) {
      final users = await _loadUsers();
      final record = users[user.email];
      if (record == null) {
        throw const AuthException('Account not found.');
      }
      final algo =
          (record['algo'] as String?) ?? PasswordHasher.algoLegacySha256;
      final ok = PasswordHasher.verify(
        password: password,
        saltBase64: record['salt'] as String,
        expectedHash: record['hash'] as String,
        algorithm: algo,
      );
      if (!ok) {
        throw const AuthException('Incorrect password.');
      }
      if (record['totpEnabled'] == true) {
        final secret = await _readTotpSecret(user.email, record);
        final code = totpCode?.trim() ?? '';
        if (secret == null || code.isEmpty || !Totp.verify(secret, code)) {
          throw const AuthException('Incorrect authenticator code.');
        }
      }
      users.remove(user.email);
      await _saveUsers(users);
      await _secure.delete(key: _totpSecretKey(user.email));
      await _secure.delete(key: _pendingTotpKey(user.email));
      await _secure.delete(key: _emailVerifyKey(user.email));
      await _secure.delete(key: _emailVerifyMetaKey(user.email));
      await _clearFailedAttempts(user.email);
    }

    await wipeLocalUserData(user: user);
    await signOut();
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
          await _setSession(await _rehydrateUser(user));
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
      final issuedAt = DateTime.tryParse(decoded['issuedAt'] as String? ?? '');
      if (issuedAt != null &&
          DateTime.now().toUtc().difference(issuedAt) > const Duration(days: 90)) {
        await _secure.delete(key: _sessionKey);
        return;
      }
      final sessionUser =
          AuthUser.fromJson(Map<String, dynamic>.from(userJson));
      _user = await _rehydrateUser(sessionUser);
    } catch (_) {
      await _secure.delete(key: _sessionKey);
    }
  }

  /// Re-read authoritative flags from the users DB (don't trust session alone).
  Future<AuthUser> _rehydrateUser(AuthUser sessionUser) async {
    if (sessionUser.provider != AuthProvider.email) return sessionUser;
    final users = await _loadUsers();
    final record = users[sessionUser.email];
    if (record == null) {
      // Stale session for a deleted account.
      await _secure.delete(key: _sessionKey);
      _user = null;
      return sessionUser;
    }
    return AuthUser(
      id: record['id'] as String? ?? sessionUser.id,
      email: sessionUser.email,
      displayName:
          record['displayName'] as String? ?? sessionUser.displayName,
      provider: AuthProvider.email,
      photoUrl: sessionUser.photoUrl,
      totpEnabled: record['totpEnabled'] == true,
      emailVerified: record.containsKey('emailVerified')
          ? record['emailVerified'] == true
          : true,
    );
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
