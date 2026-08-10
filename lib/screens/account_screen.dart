import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
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
