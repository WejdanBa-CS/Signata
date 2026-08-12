import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
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
  final _totpController = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _awaitingTotp = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  void _clearSecrets() {
    _passwordController.clear();
    _confirmController.clear();
    _totpController.clear();
    _awaitingTotp = false;
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
        _clearSecrets();
      } else {
        await AuthService.instance.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
          totpCode: _awaitingTotp ? _totpController.text : null,
        );
        _clearSecrets();
      }
    } on TotpRequiredException {
      if (!mounted) return;
      setState(() {
        _awaitingTotp = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      _clearSecrets();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      EmColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
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
                          _isSignUp
                              ? 'Accounts stay on this device. Export a recovery kit from Account after signup so you can restore your claim key later.'
                              : 'Protect images, audio, video, and PDFs — then verify ownership from any copy.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: EmColors.mutedForeground,
                            height: 1.5,
                          ),
                        ),
                        if (!AuthService.instance.isGoogleConfigured) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Google Sign-In is not configured in this build — use email, or paste a Web client ID under Account after signing in.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: EmColors.mutedForeground,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        EmCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (AuthService.instance.isGoogleConfigured) ...[
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _submitGoogle,
                                  icon: const Text(
                                    'G',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  label: const Text('Continue with Google'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                ),
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
                              ],
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
                              if (_awaitingTotp && !_isSignUp) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Enter the 6-digit code from your authenticator app.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: EmColors.mutedForeground,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _totpController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode
                                  ],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  onSubmitted: (_) => _submitEmail(),
                                  decoration: const InputDecoration(
                                    labelText: 'Authenticator code',
                                    hintText: '123456',
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
                                    : Text(_awaitingTotp && !_isSignUp
                                        ? 'Verify code'
                                        : (_isSignUp
                                            ? 'Create account'
                                            : 'Sign in with email')),
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
                                    _awaitingTotp = false;
                                    _totpController.clear();
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
                          'Email passwords stay in on-device secure storage. Google uses your Google account.',
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
