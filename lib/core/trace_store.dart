/// Persistent watchlist and sighting log for internet media tracing.
/// Data is scoped per signed-in user.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_data.dart';
import 'trace_models.dart';

class TraceStore {
  TraceStore._();
  static final TraceStore instance = TraceStore._();

  static const _legacyWatchKey = 'signata_watch_targets_v1';
  static const _legacySightingsKey = 'signata_trace_sightings_v1';
  static const _maxSightings = 150;
  static const _autoRescanCooldownKey = 'signata_trace_auto_rescan_at';

  String get _watchKey => userScopedKey(_legacyWatchKey);
  String get _sightingsKey => userScopedKey(_legacySightingsKey);
  String get _autoRescanKey => userScopedKey(_autoRescanCooldownKey);

  Future<void> _ensureMigrated() async {
    await migrateLegacyPrefsKey(_legacyWatchKey, _watchKey);
    await migrateLegacyPrefsKey(_legacySightingsKey, _sightingsKey);
  }

  Future<List<WatchTarget>> listWatchTargets() async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_watchKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(WatchTarget.fromJson).whereType<WatchTarget>().toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveWatch(List<WatchTarget> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _watchKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<WatchTarget> addWatchTarget(String url, {String? label}) async {
    await _ensureMigrated();
    final normalized = url.trim();
    final existing = List<WatchTarget>.from(await listWatchTargets());
    final prior = existing.where((w) => w.url == normalized).toList();
    if (prior.isNotEmpty) return prior.first;
    final target = WatchTarget(
      id: 'watch_${DateTime.now().millisecondsSinceEpoch}',
      url: normalized,
      addedAt: DateTime.now().toUtc(),
      label: label,
    );
    existing.insert(0, target);
    await _saveWatch(existing.take(100).toList());
    return target;
  }

  Future<void> removeWatchTarget(String id) async {
    final next = (await listWatchTargets()).where((w) => w.id != id).toList();
    await _saveWatch(next);
  }

  Future<void> touchWatchTarget(
    String id, {
    required String? reference,
  }) async {
    final items = await listWatchTargets();
    final next = items
        .map(
          (w) => w.id == id
              ? w.copyWith(
                  lastScannedAt: DateTime.now().toUtc(),
                  lastReference: reference,
                )
              : w,
        )
        .toList();
    await _saveWatch(next);
  }

  Future<List<TraceSighting>> listSightings() async {
    await _ensureMigrated();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sightingsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(TraceSighting.fromJson).whereType<TraceSighting>().toList()
        ..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return const [];
    }
  }

  Future<void> addSighting(TraceSighting sighting) async {
    await _ensureMigrated();
    final items = List<TraceSighting>.from(await listSightings());
    items.insert(0, sighting);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sightingsKey,
      jsonEncode(items.take(_maxSightings).map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearSightings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sightingsKey);
  }

  Future<void> clearWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_watchKey);
  }

  Future<void> clearAll() async {
    await clearWatchlist();
    await clearSightings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autoRescanKey);
  }

  Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    await prefs.remove('${_legacyWatchKey}__$safe');
    await prefs.remove('${_legacySightingsKey}__$safe');
    await prefs.remove('${_autoRescanCooldownKey}__$safe');
  }

  /// True if an auto-rescan should run (once per 12h when online).
  Future<bool> shouldAutoRescan({
    Duration cooldown = const Duration(hours: 12),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autoRescanKey);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().toUtc().difference(last) >= cooldown;
  }

  Future<void> markAutoRescanDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _autoRescanKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}
