import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
import '../core/claim_registry.dart';
import '../core/google_auth_config.dart';
import '../core/local_data.dart';
import '../core/share_utils.dart';
import '../core/trace_store.dart';
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
                          : (user.emailVerified
                              ? 'Email activated'
                              : 'Email account'),
                      color: EmColors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _TwoFactorCard(),
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
        const _GoogleSignInCard(),
        const SizedBox(height: 16),
        const _PrivacyDataCard(),
        const SizedBox(height: 16),
        EmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Legal'),
              const SizedBox(height: 10),
              const Text(
                'How Signata handles data on this device under Saudi PDPL. '
                'Accounts and fingerprints are local unless you configure an optional registry.',
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

class _TwoFactorCard extends StatefulWidget {
  const _TwoFactorCard();

  @override
  State<_TwoFactorCard> createState() => _TwoFactorCardState();
}

class _TwoFactorCardState extends State<_TwoFactorCard> {
  bool _busy = false;
  String? _setupSecret;
  String? _setupUri;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() => _busy = true);
    try {
      final setup = await AuthService.instance.beginTotpSetup();
      if (!mounted) return;
      setState(() {
        _setupSecret = setup.secret;
        _setupUri = setup.otpauth;
        _codeController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmSetup() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.confirmTotpSetup(_codeController.text);
      if (!mounted) return;
      setState(() {
        _setupSecret = null;
        _setupUri = null;
        _codeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication enabled.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Disable 2FA?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your password and a current authenticator code.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(labelText: 'Authenticator code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.disableTotp(
        password: _passwordController.text,
        totpCode: _codeController.text,
      );
      if (!mounted) return;
      _passwordController.clear();
      _codeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication disabled.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    if (user == null) return const SizedBox.shrink();

    if (user.provider == AuthProvider.google) {
      return EmCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MonoLabel('Two-factor auth'),
            const SizedBox(height: 10),
            const Text(
              'This Google account uses Google’s own 2FA settings. Manage them in your Google Account security page.',
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
            ),
          ],
        ),
      );
    }

    final enabled = user.totpEnabled;
    return EmCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MonoLabel('Two-factor auth'),
              const Spacer(),
              MonoLabel(
                enabled ? 'On' : 'Off',
                color: enabled ? EmColors.accent : EmColors.mutedForeground,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            enabled
                ? 'Sign-in requires your password plus a code from an authenticator app (Google Authenticator, Authy, etc.).'
                : 'Add an authenticator app for a second step after your password. Secrets stay on this device.',
            style: const TextStyle(
                fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
          ),
          const SizedBox(height: 14),
          if (_setupSecret != null) ...[
            const Text(
              'Add this key in your authenticator app, then enter the 6-digit code:',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 10),
            SelectableText(
              _setupSecret!,
              style: emMono(size: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _setupSecret!));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Secret copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy secret'),
                ),
                if (_setupUri != null)
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _setupUri!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('otpauth link copied')),
                      );
                    },
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Copy setup link'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Confirm code',
                hintText: '123456',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _confirmSetup,
              child: const Text('Confirm & enable'),
            ),
          ] else if (enabled)
            OutlinedButton.icon(
              onPressed: _busy ? null : _disable,
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Disable 2FA'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _startSetup,
              icon: const Icon(Icons.phonelink_lock_outlined, size: 18),
              label: const Text('Enable 2FA'),
            ),
        ],
      ),
    );
  }
}

class _PrivacyDataCard extends StatelessWidget {
  const _PrivacyDataCard();

  Future<void> _exportRecovery(BuildContext context) async {
    try {
      final kit = await buildRecoveryKit();
      final bytes = Uint8List.fromList(utf8.encode(kit));
      await shareBytes(
        bytes: bytes,
        fileName: 'signata-recovery-kit.txt',
        mimeType: 'text/plain',
        text: 'Signata recovery kit — keep offline and private.',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _importRecovery(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Import recovery kit?'),
        content: const Text(
          'This replaces your claim key on this device with the key from the '
          'kit. Only do this when restoring the same Signata identity.\n\n'
          'Fingerprints sealed with a different key will no longer show as '
          'authenticated for this account.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'kit', 'text'],
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final kid = await importRecoveryKit(utf8.decode(bytes));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claim key restored (kid $kid).')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _clearClaims(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Clear published claims?'),
        content: const Text(
          'Removes local claim catalog entries on this device. '
          'Watermarked files keep their embedded fingerprints.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ClaimRegistry.instance.clearLocal();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Published claims cleared.')),
    );
  }

  Future<void> _clearTrace(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Clear Trace data?'),
        content: const Text(
          'Removes your watchlist and sighting timeline on this device. '
          'Protected files are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TraceStore.instance.clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trace data cleared.')),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = AuthService.instance.user;
    if (user == null) return;
    final passwordController = TextEditingController();
    final totpController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Delete local account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This erases your Signata account record, claim key, history, '
              'Trace data, and usage flags on this device. Watermarked files '
              'you already exported are not deleted from storage.',
              style: TextStyle(height: 1.45),
            ),
            if (user.provider == AuthProvider.email) ...[
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (user.totpEnabled) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: totpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration:
                      const InputDecoration(labelText: 'Authenticator code'),
                ),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Google sessions only need this confirmation — no password.',
                  style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: EmColors.destructive,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    final password = passwordController.text;
    final totp = totpController.text;
    passwordController.dispose();
    totpController.dispose();
    if (confirmed != true) return;
    try {
      await AuthService.instance.deleteAccount(
        password: password,
        totpCode: totp.isEmpty ? null : totp,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('Privacy & data'),
          const SizedBox(height: 10),
          const Text(
            'Export a recovery kit before wiping this device. Import it after '
            'reinstall to keep authenticating old fingerprints. Clear Trace or '
            'claims anytime. Delete account removes local Signata identity data.',
            style: TextStyle(
                fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportRecovery(context),
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('Export recovery kit'),
              ),
              OutlinedButton.icon(
                onPressed: () => _importRecovery(context),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import recovery kit'),
              ),
              OutlinedButton.icon(
                onPressed: () => _clearTrace(context),
                icon: const Icon(Icons.radar_outlined, size: 18),
                label: const Text('Clear Trace data'),
              ),
              OutlinedButton.icon(
                onPressed: () => _clearClaims(context),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Clear claims'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deleteAccount(context),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Delete account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EmColors.destructive,
                  side: BorderSide(
                      color: EmColors.destructive.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoogleSignInCard extends StatefulWidget {
  const _GoogleSignInCard();

  @override
  State<_GoogleSignInCard> createState() => _GoogleSignInCardState();
}

class _GoogleSignInCardState extends State<_GoogleSignInCard> {
  bool _busy = false;

  Future<void> _configure() async {
    final controller = TextEditingController(
      text: GoogleAuthConfig.hasServerClientId && !GoogleAuthConfig.isFromDartDefine
          ? GoogleAuthConfig.serverClientId
          : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Google Web client ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the OAuth Web application client ID from Google Cloud. '
              'Also add Android clients with package app.signata.signata and '
              'your SHA-1s (see docs/RELEASE_PLAY.md).',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Web client ID',
                hintText: '….apps.googleusercontent.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = controller.text;
    controller.dispose();
    if (saved != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.instance.configureGoogleServerClientId(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Sign-In configured. Sign out and try Google.'),
        ),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = AuthService.instance.isGoogleConfigured;
    return EmCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MonoLabel('Google Sign-In'),
              const Spacer(),
              MonoLabel(
                configured ? 'Ready' : 'Not configured',
                color: configured ? EmColors.accent : EmColors.destructive,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            configured
                ? (GoogleAuthConfig.isFromDartDefine
                    ? 'Using the Web client ID baked into this build.'
                    : 'Using a Web client ID saved on this device.')
                : 'Email login works without Google. To enable Continue with Google, '
                    'paste your Web client ID here or build with google_oauth.env.',
            style: const TextStyle(
                fontSize: 13, height: 1.45, color: EmColors.mutedForeground),
          ),
          if (kDebugMode || !configured) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _configure,
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: Text(configured ? 'Update Web client ID' : 'Paste Web client ID'),
            ),
          ],
        ],
      ),
    );
  }
}
