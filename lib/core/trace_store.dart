/// Persistent watchlist and sighting log for internet media tracing.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trace_models.dart';

class TraceStore {
  TraceStore._();
  static final TraceStore instance = TraceStore._();

  static const _watchKey = 'signata_watch_targets_v1';
  static const _sightingsKey = 'signata_trace_sightings_v1';
  static const _maxSightings = 150;

  Future<List<WatchTarget>> listWatchTargets() async {
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
    final normalized = url.trim();
    final existing = await listWatchTargets();
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
    final items = await listSightings();
    items.insert(0, sighting);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sightingsKey,
      jsonEncode(items.take(_maxSightings).map((e) => e.toJson()).toList()),
    );
  }
}
