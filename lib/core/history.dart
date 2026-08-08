/// Local verification history — an app-only improvement over the website.
/// Every embed/verify run is recorded on-device so creators can look back at
/// what they protected and when.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  /// "image" | "pdf"
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
    if (value is! Map<String, dynamic>) return null;
    try {
      return HistoryEntry(
        medium: value['medium'] as String,
        action: value['action'] as String,
        subject: value['subject'] as String,
        owner: value['owner'] as String,
        verified: value['verified'] as bool,
        reference: value['reference'] as String,
        at: DateTime.parse(value['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class HistoryStore {
  static const _key = 'em_history_v1';
  static const _maxEntries = 100;

  static Future<List<HistoryEntry>> load() async {
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
}
