import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth.dart';
import '../core/google_auth_config.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import 'privacy_policy_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearSecrets() {
    _passwordController.clear();
    _confirmController.clear();
  }

  Future<void> _submitEmail() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await AuthService.instance.signUpWithEmail(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          confirmPassword: _confirmController.text,
        );
      } else {
        await AuthService.instance.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      _clearSecrets();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    if (!AuthService.instance.isGoogleConfigured) {
      final configured = await _showGoogleSetupDialog();
      if (!configured) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      _clearSecrets();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _error = message);
      if (message.toLowerCase().contains('client') ||
          message.toLowerCase().contains('setup') ||
          message.toLowerCase().contains('oauth')) {
        await _showGoogleSetupDialog();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showGoogleSetupDialog() async {
    final controller = TextEditingController(
      text: GoogleAuthConfig.serverClientId,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: EmColors.card,
          title: const Text('Set up Google Sign-In'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Create two OAuth clients in Google Cloud, then paste the Web client ID here.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: EmColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '1. Open Credentials → Create OAuth client',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '• Web application → copy its Client ID\n'
                  '• Android → package + BOTH SHA-1s below (no need to paste that ID)',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: EmColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Package: ${GoogleAuthConfig.androidPackageName}\n'
                  'Debug SHA-1: ${GoogleAuthConfig.androidDebugSha1}\n'
                  'Release SHA-1: ${GoogleAuthConfig.androidReleaseSha1}',
                  style: emMono(size: 11),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: GoogleAuthConfig.androidDebugSha1,
                        ));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Debug SHA-1 copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy debug SHA-1'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: GoogleAuthConfig.androidReleaseSha1,
                        ));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Release SHA-1 copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy release SHA-1'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(
                          'https://console.cloud.google.com/apis/credentials',
                        );
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open Cloud Console'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Web client ID',
                    hintText: '123-abc.apps.googleusercontent.com',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await AuthService.instance
                      .configureGoogleServerClientId(controller.text);
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save & continue'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return saved == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final googleReady = AuthService.instance.isGoogleConfigured;

    return Scaffold(
      body: Stack(
        children: [
          const GridBackdrop(spacing: 48, opacity: 0.05),
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: EmColors.primary.withValues(alpha: 0.2),
                      blurRadius: 120,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const EmLogo(size: 36),
                        const SizedBox(height: 28),
                        const MonoLabel('Welcome'),
                        const SizedBox(height: 12),
                        Text(
                          _isSignUp
                              ? 'Create your account'
                              : 'Sign in to Signata',
                          style: theme.textTheme.displayMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Protect images, audio, video, and PDFs — then verify ownership from any copy.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: EmColors.mutedForeground,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        EmCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _submitGoogle,
                                icon: const Icon(Icons.g_mobiledata, size: 28),
                                label: Text(
                                  googleReady
                                      ? 'Continue with Google'
                                      : 'Continue with Google (setup)',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                              ),
                              if (!googleReady) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final ok =
                                              await _showGoogleSetupDialog();
                                          if (ok && mounted) setState(() {});
                                        },
                                  child: const Text('Set up Google Sign-In'),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text('OR EMAIL',
                                        style: emMonoLabel(
                                            color: EmColors.mutedForeground,
                                            size: 9)),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 18),
                              if (_isSignUp) ...[
                                TextField(
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: const InputDecoration(
                                    labelText: 'Display name',
                                    hintText: 'Your name',
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: [
                                  if (_isSignUp) AutofillHints.newUsername,
                                  AutofillHints.email,
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(
                                      RegExp(r'\s')),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  hintText: 'you@example.com',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscure,
                                textInputAction: _isSignUp
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                onSubmitted:
                                    _isSignUp ? null : (_) => _submitEmail(),
                                autofillHints: [
                                  _isSignUp
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: _isSignUp
                                      ? '${PasswordPolicy.minLength}+ chars, letter & number'
                                      : 'Your password',
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(_obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                              if (_isSignUp) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirmController,
                                  obscureText: _obscureConfirm,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitEmail(),
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Confirm password',
                                    hintText: 'Re-enter password',
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                          () => _obscureConfirm =
                                              !_obscureConfirm),
                                      icon: Icon(_obscureConfirm
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                    ),
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                StatusBanner(
                                  ok: false,
                                  title: 'Could not continue',
                                  subtitle: _error!,
                                ),
                              ],
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _busy ? null : _submitEmail,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Text(_isSignUp
                                        ? 'Create account'
                                        : 'Sign in with email'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _isSignUp = !_isSignUp;
                                    _error = null;
                                    _confirmController.clear();
                                  }),
                          child: Text(
                            _isSignUp
                                ? 'Already have an account? Sign in'
                                : 'New here? Create an account',
                            style: const TextStyle(color: EmColors.primary),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => PrivacyPolicyScreen.open(context),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: EmColors.mutedForeground,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          googleReady
                              ? 'Email passwords stay in on-device secure storage. Google uses your Google account.'
                              : 'Google Sign-In needs a one-time OAuth setup (Web + Android clients). Email login works without it.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: EmColors.mutedForeground,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
