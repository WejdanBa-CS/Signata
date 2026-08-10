/// Freemium usage gate (demo build).
///
/// Free plan: [freeProtectsPerDay] protect runs and [freeTracePerDay] Trace
/// scans per calendar day, per signed-in user. A mock rewarded ad grants +1
/// of the blocked action for today; a mock purchase unlocks Premium, which
/// removes both limits. Counters and the premium flag are stored locally in
/// SharedPreferences, keyed by user id.
///
/// The mock [BillingGateway] and [RewardedAdGateway] are the seams to swap in
/// real Play Billing / AdMob later without touching the gating logic.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';

/// Which gated action is being consumed.
enum UsageKind { protect, trace }

/// Result of trying to reserve an attempt.
enum GateResult { allowed, blocked }

class UsageSnapshot {
  const UsageSnapshot({
    required this.isPremium,
    required this.protectUsed,
    required this.protectLimit,
    required this.traceUsed,
    required this.traceLimit,
  });

  final bool isPremium;
  final int protectUsed;
  final int protectLimit;
  final int traceUsed;
  final int traceLimit;

  int get protectRemaining =>
      isPremium ? 1 << 30 : (protectLimit - protectUsed).clamp(0, 1 << 30);
  int get traceRemaining =>
      isPremium ? 1 << 30 : (traceLimit - traceUsed).clamp(0, 1 << 30);

  int remainingFor(UsageKind kind) =>
      kind == UsageKind.protect ? protectRemaining : traceRemaining;
}

/// Seam for a real billing SDK later. The demo build just succeeds.
class BillingGateway {
  const BillingGateway();

  Future<bool> purchasePremium() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return true;
  }
}

/// Seam for a real rewarded-ad SDK later. The demo build just succeeds.
class RewardedAdGateway {
  const RewardedAdGateway();

  Future<bool> show() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return true;
  }
}

class UsageEntitlements {
  UsageEntitlements._();

  static final instance = UsageEntitlements._();

  static const freeProtectsPerDay = 2;
  static const freeTracePerDay = 1;

  final billing = const BillingGateway();
  final rewardedAd = const RewardedAdGateway();

  /// Overridable in tests to simulate day rollover.
  String Function() todayKey = _defaultTodayKey;

  /// Overridable in tests to avoid a signed-in user.
  String Function() userId = _defaultUserId;

  static String _defaultTodayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String _defaultUserId() =>
      AuthService.instance.user?.id ?? 'anonymous';

  String get _prefsKey => 'signata.usage.${userId()}';

  Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(SharedPreferences prefs, Map<String, dynamic> data) =>
      prefs.setString(_prefsKey, jsonEncode(data));

  /// Counters for today only; stale days reset to zero implicitly.
  ({int protect, int trace, int protectBonus, int traceBonus}) _todayCounters(
      Map<String, dynamic> data) {
    if (data['day'] != todayKey()) {
      return (protect: 0, trace: 0, protectBonus: 0, traceBonus: 0);
    }
    int asInt(Object? v) => v is int ? v : 0;
    return (
      protect: asInt(data['protect']),
      trace: asInt(data['trace']),
      protectBonus: asInt(data['protectBonus']),
      traceBonus: asInt(data['traceBonus']),
    );
  }

  Future<UsageSnapshot> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    final c = _todayCounters(data);
    return UsageSnapshot(
      isPremium: data['premium'] == true,
      protectUsed: c.protect,
      protectLimit: freeProtectsPerDay + c.protectBonus,
      traceUsed: c.trace,
      traceLimit: freeTracePerDay + c.traceBonus,
    );
  }

  Future<bool> get isPremium async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    return data['premium'] == true;
  }

  /// Consumes one attempt of [kind] if available. Premium always allows
  /// without consuming.
  Future<GateResult> reserve(UsageKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    if (data['premium'] == true) return GateResult.allowed;

    final c = _todayCounters(data);
    final used = kind == UsageKind.protect ? c.protect : c.trace;
    final limit = kind == UsageKind.protect
        ? freeProtectsPerDay + c.protectBonus
        : freeTracePerDay + c.traceBonus;
    if (used >= limit) return GateResult.blocked;

    await _save(prefs, {
      'premium': data['premium'] == true,
      'day': todayKey(),
      'protect': c.protect + (kind == UsageKind.protect ? 1 : 0),
      'trace': c.trace + (kind == UsageKind.trace ? 1 : 0),
      'protectBonus': c.protectBonus,
      'traceBonus': c.traceBonus,
    });
    return GateResult.allowed;
  }

  Future<GateResult> reserveProtect() => reserve(UsageKind.protect);

  Future<GateResult> reserveTrace() => reserve(UsageKind.trace);

  /// Rewarded-ad bonus: +1 attempt of [kind] valid for today.
  Future<void> grantAdBonus({required UsageKind kind}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    final c = _todayCounters(data);
    await _save(prefs, {
      'premium': data['premium'] == true,
      'day': todayKey(),
      'protect': c.protect,
      'trace': c.trace,
      'protectBonus': c.protectBonus + (kind == UsageKind.protect ? 1 : 0),
      'traceBonus': c.traceBonus + (kind == UsageKind.trace ? 1 : 0),
    });
  }

  Future<void> unlockPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    data['premium'] = true;
    await _save(prefs, data);
  }

  Future<void> clearPremiumForDebug() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await _load(prefs);
    data['premium'] = false;
    await _save(prefs, data);
  }
}
