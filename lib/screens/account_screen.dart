import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/usage_entitlements.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import '../widgets/usage_paywall.dart';
import 'privacy_policy_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    if (user == null) {
      return const Center(child: Text('Not signed in'));
    }

    final initial = user.displayName.isNotEmpty
        ? user.displayName.characters.first.toUpperCase()
        : '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const SectionHeading(
          tag: 'Account',
          title: 'Your Signata identity',
          desc: 'Signed-in creators are the default owner claim in every tool.',
        ),
        const SizedBox(height: 20),
        EmCard(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: EmColors.primary.withValues(alpha: 0.15),
                backgroundImage:
                    user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                child: user.photoUrl == null
                    ? Text(initial,
                        style: const TextStyle(
                            color: EmColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: EmColors.foreground)),
                    const SizedBox(height: 4),
                    Text(user.email,
                        style: const TextStyle(
                            fontSize: 13, color: EmColors.mutedForeground)),
                    const SizedBox(height: 8),
                    MonoLabel(
                      user.provider == AuthProvider.google
                          ? 'Google account'
                          : 'Email account',
                      color: EmColors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Session'),
              const SizedBox(height: 10),
              const Text(
                'Your session is stored in on-device secure storage. Sign out anytime — watermarked files are not affected.',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: EmColors.mutedForeground),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => AuthService.instance.signOut(),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EmColors.destructive,
                  side: BorderSide(
                      color: EmColors.destructive.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _PlanCard(),
        const SizedBox(height: 16),
        EmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Legal'),
              const SizedBox(height: 10),
              const Text(
                'How Signata collects, uses, and protects your data under Saudi PDPL.',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: EmColors.mutedForeground),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => PrivacyPolicyScreen.open(context),
                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                label: const Text('Privacy Policy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plan status + quota + mock premium purchase.
class _PlanCard extends StatefulWidget {
  const _PlanCard();

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  UsageSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final snapshot = await UsageEntitlements.instance.snapshot();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  Future<void> _goPremium() async {
    final purchased = await purchasePremiumFlow(context);
    if (purchased) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return EmCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MonoLabel('Plan'),
              const Spacer(),
              if (snap != null)
                MonoLabel(
                  snap.isPremium ? 'Premium' : 'Free',
                  color: snap.isPremium ? EmColors.accent : EmColors.primary,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (snap == null)
            const Text(
              'Loading plan…',
              style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
            )
          else if (snap.isPremium)
            const Text(
              'Unlimited protects and Trace scans. Thanks for supporting Signata.',
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
            )
          else ...[
            Text(
              '${snap.protectRemaining} of ${snap.protectLimit} free protects and '
              '${snap.traceRemaining} of ${snap.traceLimit} free Trace scans left today. '
              'Watch an ad for extras, or go Premium for unlimited use.',
              style: const TextStyle(
                  fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _goPremium,
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Go Premium'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demo billing — real Play Billing / AdMob come later.',
              style: TextStyle(fontSize: 11.5, color: EmColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
