import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signata/core/usage_entitlements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final entitlements = UsageEntitlements.instance;
  var day = '2026-08-10';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    day = '2026-08-10';
    entitlements.todayKey = () => day;
    entitlements.userId = () => 'test_user';
  });

  test('fresh user gets freeProtects and freeTrace, then blocked', () async {
    for (var i = 0; i < UsageEntitlements.freeProtectsPerDay; i++) {
      expect(await entitlements.reserveProtect(), GateResult.allowed);
    }
    expect(await entitlements.reserveProtect(), GateResult.blocked);

    for (var i = 0; i < UsageEntitlements.freeTracePerDay; i++) {
      expect(await entitlements.reserveTrace(), GateResult.allowed);
    }
    expect(await entitlements.reserveTrace(), GateResult.blocked);
  });

  test('check does not consume; commit does', () async {
    expect(await entitlements.check(UsageKind.protect), GateResult.allowed);
    expect(await entitlements.check(UsageKind.protect), GateResult.allowed);
    expect(await entitlements.commit(UsageKind.protect), GateResult.allowed);
    final snap = await entitlements.snapshot();
    expect(snap.protectUsed, 1);
  });

  test('ad bonus grants one extra attempt of that kind only', () async {
    for (var i = 0; i < UsageEntitlements.freeProtectsPerDay; i++) {
      expect(await entitlements.reserveProtect(), GateResult.allowed);
    }
    expect(await entitlements.reserveProtect(), GateResult.blocked);

    await entitlements.grantAdBonus(kind: UsageKind.protect);
    expect(await entitlements.reserveProtect(), GateResult.allowed);
    expect(await entitlements.reserveProtect(), GateResult.blocked);

    for (var i = 0; i < UsageEntitlements.freeTracePerDay; i++) {
      expect(await entitlements.reserveTrace(), GateResult.allowed);
    }
    expect(await entitlements.reserveTrace(), GateResult.blocked);
    await entitlements.grantAdBonus(kind: UsageKind.trace);
    expect(await entitlements.reserveTrace(), GateResult.allowed);
  });

  test('premium bypasses both limits without consuming', () async {
    await entitlements.unlockPremium();
    for (var i = 0; i < 5; i++) {
      expect(await entitlements.reserveProtect(), GateResult.allowed);
      expect(await entitlements.reserveTrace(), GateResult.allowed);
    }
    final snap = await entitlements.snapshot();
    expect(snap.isPremium, isTrue);
    expect(snap.protectUsed, 0);
  });

  test('day rollover resets counters and ad bonuses', () async {
    await entitlements.grantAdBonus(kind: UsageKind.protect);
    for (var i = 0; i < UsageEntitlements.freeProtectsPerDay + 1; i++) {
      expect(await entitlements.reserveProtect(), GateResult.allowed);
    }
    expect(await entitlements.reserveProtect(), GateResult.blocked);
    expect(await entitlements.reserveTrace(), GateResult.allowed);

    day = '2026-08-11';
    final snap = await entitlements.snapshot();
    expect(snap.protectUsed, 0);
    expect(snap.protectLimit, UsageEntitlements.freeProtectsPerDay);
    expect(await entitlements.reserveProtect(), GateResult.allowed);
  });

  test('quotas are per user id', () async {
    for (var i = 0; i < UsageEntitlements.freeTracePerDay; i++) {
      expect(await entitlements.reserveTrace(), GateResult.allowed);
    }
    expect(await entitlements.reserveTrace(), GateResult.blocked);

    entitlements.userId = () => 'other_user';
    expect(await entitlements.reserveTrace(), GateResult.allowed);
  });

  test('premium survives day rollover', () async {
    await entitlements.unlockPremium();
    day = '2026-08-12';
    expect(await entitlements.isPremium, isTrue);
    expect(await entitlements.reserveProtect(), GateResult.allowed);
  });

  test('snapshot reports remaining correctly', () async {
    var snap = await entitlements.snapshot();
    expect(snap.protectRemaining, UsageEntitlements.freeProtectsPerDay);
    expect(snap.traceRemaining, UsageEntitlements.freeTracePerDay);

    await entitlements.reserveProtect();
    snap = await entitlements.snapshot();
    expect(snap.protectRemaining, UsageEntitlements.freeProtectsPerDay - 1);
    expect(snap.remainingFor(UsageKind.protect),
        UsageEntitlements.freeProtectsPerDay - 1);
    expect(snap.remainingFor(UsageKind.trace),
        UsageEntitlements.freeTracePerDay);
  });
}
