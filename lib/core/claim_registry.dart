/// Local + optional remote registry of published Signata claims.
///
/// Local storage always works. When `SIGNATA_REGISTRY_URL` is set (dart-define
/// or [ClaimRegistry.configure]), claims are also POSTed so other devices can
/// look them up by fingerprint reference.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'local_data.dart';
import 'trace_models.dart';

class ClaimRegistry {
  ClaimRegistry._();
  static final ClaimRegistry instance = ClaimRegistry._();

  static const _legacyPrefsKey = 'signata_published_claims_v1';

  /// Optional remote base URL, e.g. `https://registry.example.com`.
  static String remoteBaseUrl = const String.fromEnvironment(
    'SIGNATA_REGISTRY_URL',
    defaultValue: '',
  );

  static void configure({String? remoteBaseUrl}) {
    if (remoteBaseUrl != null) ClaimRegistry.remoteBaseUrl = remoteBaseUrl;
  }

  static bool get hasRemote => remoteBaseUrl.trim().isNotEmpty;

  String get _prefsKey => userScopedKey(_legacyPrefsKey);

  Future<void> _ensureMigrated() =>
      migrateLegacyPrefsKey(_legacyPrefsKey, _prefsKey);

  Future<List<PublishedClaim>> listLocal() async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map(PublishedClaim.fromJson)
          .whereType<PublishedClaim>()
          .toList()
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveLocal(List<PublishedClaim> claims) async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(claims.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    await prefs.remove('${_legacyPrefsKey}__$safe');
  }

  Future<PublishedClaim?> findByReference(String reference) async {
    final needle = reference.trim().toUpperCase();
    if (needle.isEmpty) return null;
    for (final claim in await listLocal()) {
      if (claim.reference.toUpperCase() == needle) return claim;
    }
    if (hasRemote) {
      try {
        final uri = Uri.parse('${remoteBaseUrl.replaceAll(RegExp(r'/+$'), '')}'
            '/claims/${Uri.encodeComponent(reference)}');
        final response = await http.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final map = decoded is Map && decoded['claim'] is Map
              ? decoded['claim']
              : decoded;
          return PublishedClaim.fromJson(map);
        }
      } catch (error) {
        debugPrint('Remote claim lookup failed: $error');
      }
    }
    return null;
  }

  Future<PublishedClaim> publish({
    required TraceMedium medium,
    required String owner,
    required String subject,
    required String reference,
    required String issued,
    String? alg,
    String? kid,
    String? note,
  }) async {
    final user = AuthService.instance.user;
    final id =
        'claim_${DateTime.now().toUtc().millisecondsSinceEpoch}_$reference';
    var claim = PublishedClaim(
      id: id,
      medium: medium,
      owner: owner,
      subject: subject,
      reference: reference,
      issued: issued,
      publisherId: user?.id ?? 'anonymous',
      publishedAt: DateTime.now().toUtc(),
      alg: alg,
      kid: kid,
      note: note,
    );

    if (hasRemote) {
      try {
        final uri = Uri.parse(
            '${remoteBaseUrl.replaceAll(RegExp(r'/+$'), '')}/claims');
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                // Optional shared secret for self-hosted registries.
                if (const String.fromEnvironment('SIGNATA_REGISTRY_TOKEN')
                    .isNotEmpty)
                  'Authorization':
                      'Bearer ${const String.fromEnvironment('SIGNATA_REGISTRY_TOKEN')}',
              },
              body: jsonEncode(claim.toJson()),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          claim = claim.copyWith(remoteSynced: true);
        } else {
          debugPrint(
            'Remote publish failed: ${response.statusCode} ${response.body}',
          );
        }
      } catch (error) {
        debugPrint('Remote publish error: $error');
      }
    }

    final existing = await listLocal();
    final withoutDup = existing
        .where((c) => c.reference.toUpperCase() != reference.toUpperCase())
        .toList();
    withoutDup.insert(0, claim);
    await _saveLocal(withoutDup.take(200).toList());
    return claim;
  }

  Future<void> remove(String id) async {
    final next = (await listLocal()).where((c) => c.id != id).toList();
    await _saveLocal(next);
  }
}
