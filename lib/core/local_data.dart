/// Per-user local data helpers and full wipe for account deletion / privacy.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'claim_crypto.dart';
import 'claim_registry.dart';
import 'history.dart';
import 'trace_store.dart';
import 'usage_entitlements.dart';

/// Prefs key scoped to the signed-in user (falls back to anonymous).
String userScopedKey(String base) {
  final id = AuthService.instance.user?.id ?? 'anonymous';
  final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return '${base}__$safe';
}

/// One-shot migration: copy legacy global [legacyKey] into the current user's
/// scoped key when the scoped key is empty.
Future<void> migrateLegacyPrefsKey(String legacyKey, String scopedKey) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey(scopedKey)) return;
  final raw = prefs.getString(legacyKey);
  if (raw == null || raw.isEmpty) return;
  await prefs.setString(scopedKey, raw);
}

  /// Offline recovery kit text (claim key + account hints). Store safely offline.
  Future<String> buildRecoveryKit() async {
    final user = AuthService.instance.user;
    if (user == null) {
      throw const AuthException('Not signed in.');
    }
    final keyB64 = await AccountClaimKeys.exportCurrentKeyBase64() ??
        base64UrlEncode((await AccountClaimKeys.forUser(user.id)).bytes);
    return '''
Signata recovery kit
====================
Generated: ${DateTime.now().toUtc().toIso8601String()}
Email: ${user.email}
Account id: ${user.id}
Provider: ${user.provider.name}

Claim key (base64url) — required to prove old fingerprints as "yours":
$keyB64

Keep this file offline and private. Signata accounts are local to this device;
losing the password and this kit may permanently lock you out of authentication.
'''.trim();
  }

  /// Erases all on-device Signata data for [user] (or the current user).
  Future<void> wipeLocalUserData({AuthUser? user}) async {
  final target = user ?? AuthService.instance.user;
  if (target == null) return;

  await HistoryStore.clearForUser(target.id);
  await TraceStore.instance.clearForUser(target.id);
  await ClaimRegistry.instance.clearForUser(target.id);
  await UsageEntitlements.instance.clearForUser(target.id);
  await AccountClaimKeys.deleteForUser(target.id);
}
