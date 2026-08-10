/// Paywall dialog + quota banner for the demo freemium gate.
///
/// `ensureUsage` reserves an attempt; when the daily quota is exhausted it
/// shows a dialog offering a mock rewarded ad (+1 today) or a mock Premium
/// purchase (removes limits). Returns true when the caller may proceed.
library;

import 'package:flutter/material.dart';

import '../core/usage_entitlements.dart';
import '../theme.dart';

/// Reserve one [kind] attempt, showing the paywall when blocked.
Future<bool> ensureUsage(BuildContext context, UsageKind kind) async {
  final entitlements = UsageEntitlements.instance;
  if (await entitlements.reserve(kind) == GateResult.allowed) return true;
  if (!context.mounted) return false;

  final choice = await showDialog<_PaywallChoice>(
    context: context,
    builder: (context) => _PaywallDialog(kind: kind),
  );
  if (choice == null || !context.mounted) return false;

  switch (choice) {
    case _PaywallChoice.watchAd:
      final watched = await _showMockAd(context);
      if (!watched) return false;
      await entitlements.grantAdBonus(kind: kind);
      return await entitlements.reserve(kind) == GateResult.allowed;
    case _PaywallChoice.goPremium:
      final purchased = await purchasePremiumFlow(context);
      return purchased;
  }
}

/// Mock purchase flow, also used from the Account screen.
Future<bool> purchasePremiumFlow(BuildContext context) async {
  final entitlements = UsageEntitlements.instance;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: EmColors.card,
      title: const Text('Go Premium'),
      content: const Text(
        'Unlimited protects and Trace scans, no daily limits.\n\n'
        'Demo build: this simulates a purchase — no real payment is made.',
        style: TextStyle(height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buy Premium'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final ok = await _showProgress(
    context,
    label: 'Processing purchase…',
    task: entitlements.billing.purchasePremium(),
  );
  if (!ok) return false;
  await entitlements.unlockPremium();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Premium unlocked — limits removed.')),
    );
  }
  return true;
}

Future<bool> _showMockAd(BuildContext context) => _showProgress(
      context,
      label: 'Playing ad… (demo)',
      task: UsageEntitlements.instance.rewardedAd.show(),
    );

Future<bool> _showProgress(
  BuildContext context, {
  required String label,
  required Future<bool> task,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: EmColors.card,
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: EmColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  );
  final result = await task;
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  return result;
}

enum _PaywallChoice { watchAd, goPremium }

class _PaywallDialog extends StatelessWidget {
  const _PaywallDialog({required this.kind});

  final UsageKind kind;

  @override
  Widget build(BuildContext context) {
    final what = kind == UsageKind.protect
        ? 'free protects (${UsageEntitlements.freeProtectsPerDay}/day)'
        : 'free Trace scan (${UsageEntitlements.freeTracePerDay}/day)';
    return AlertDialog(
      backgroundColor: EmColors.card,
      title: const Text('Daily limit reached'),
      content: Text(
        'You have used your $what.\n\n'
        'Watch a short ad for one more, or go Premium for unlimited use.',
        style: const TextStyle(height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _PaywallChoice.watchAd),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Watch ad'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _PaywallChoice.goPremium),
          icon: const Icon(Icons.workspace_premium_outlined, size: 18),
          label: const Text('Go Premium'),
        ),
      ],
    );
  }
}

/// Small quota banner for tool screens ("2 free protects left today").
class UsageStatusBanner extends StatelessWidget {
  const UsageStatusBanner({super.key, required this.kind});

  final UsageKind kind;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsageSnapshot>(
      future: UsageEntitlements.instance.snapshot(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();

        final String text;
        final Color color;
        if (data.isPremium) {
          text = 'Premium — unlimited use';
          color = EmColors.accent;
        } else {
          final left = data.remainingFor(kind);
          final noun = kind == UsageKind.protect
              ? 'free protect${left == 1 ? '' : 's'}'
              : 'free Trace scan${left == 1 ? '' : 's'}';
          text = left > 0
              ? '$left $noun left today'
              : 'Daily limit reached — watch an ad or go Premium';
          color = left > 0 ? EmColors.primary : EmColors.destructive;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(
                data.isPremium
                    ? Icons.workspace_premium_outlined
                    : Icons.timelapse_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 12.5, color: color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
