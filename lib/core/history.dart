/// Local verification history — an app-only improvement over the website.
/// Every embed/verify run is recorded on-device so creators can look back at
/// what they protected and when. Entries are scoped per signed-in user.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_data.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.medium,
    required this.action,
    required this.subject,
    required this.owner,
    required this.verified,
    required this.reference,
    required this.at,
  });

  /// "image" | "audio" | "video" | "pdf"
  final String medium;

  /// "embed" | "verify"
  final String action;
  final String subject;
  final String owner;
  final bool verified;

  /// Signature or structural identifier (shortened for display).
  final String reference;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'medium': medium,
        'action': action,
        'subject': subject,
        'owner': owner,
        'verified': verified,
        'reference': reference,
        'at': at.toIso8601String(),
      };

  static HistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    try {
      return HistoryEntry(
        medium: map['medium'] as String,
        action: map['action'] as String,
        subject: map['subject'] as String,
        owner: map['owner'] as String,
        verified: map['verified'] as bool,
        reference: map['reference'] as String,
        at: DateTime.parse(map['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class HistoryStore {
  static const _legacyKey = 'signata_history_v1';
  static const _maxEntries = 100;

  static String get _key => userScopedKey(_legacyKey);

  static Future<void> _ensureMigrated() =>
      migrateLegacyPrefsKey(_legacyKey, _key);

  static Future<List<HistoryEntry>> load() async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map((e) => HistoryEntry.fromJson(e as Object?))
          .whereType<HistoryEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(HistoryEntry entry) async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    final entries = await load();
    final updated = [entry, ...entries].take(_maxEntries).toList();
    await prefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    await prefs.remove('${_legacyKey}__$safe');
  }
}
