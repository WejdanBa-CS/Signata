import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';

/// Blocks the app until the user activates their on-device email account.
///
/// Signata does not run a mail server — the code is generated on-device and
/// optionally drafted via mailto for the user to save.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  bool _showCode = false;
  String? _error;
  String? _info;
  String? _plainCode;

  @override
  void initState() {
    super.initState();
    _info =
        'Signata creates an activation code on this device (no email server). '
        'We can open a mailto draft so you can save it — or show the code here.';
    WidgetsBinding.instance.addPostFrameCallback((_) => _issueCode(silent: true));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _issueCode({bool silent = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!silent) _info = null;
    });
    try {
      final code = await AuthService.instance.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _plainCode = code.isEmpty ? _plainCode : code;
        _info = silent
            ? _info
            : 'New code ready. Open your mail draft or reveal the code below.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.confirmEmailVerification(_codeController.text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.user?.email ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const GridBackdrop(spacing: 48, opacity: 0.05),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EmLogo(size: 36),
                      const SizedBox(height: 28),
                      const MonoLabel('Activate account'),
                      const SizedBox(height: 12),
                      Text('Finish setup',
                          style: theme.textTheme.displayMedium),
                      const SizedBox(height: 10),
                      Text(
                        'Enter the activation code for $email. This is a local '
                        'device step — not remote email ownership proof.',
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
                            if (_info != null) ...[
                              Text(
                                _info!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: EmColors.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_plainCode != null) ...[
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _showCode = !_showCode),
                                icon: Icon(
                                  _showCode
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _showCode ? 'Hide code' : 'Show code on device',
                                ),
                              ),
                              if (_showCode) ...[
                                const SizedBox(height: 10),
                                SelectableText(
                                  _plainCode!,
                                  style: emMonoLabel(size: 22).copyWith(
                                    letterSpacing: 4,
                                    color: EmColors.primary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: _plainCode!),
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Code copied'),
                                      ),
                                    );
                                  },
                                  child: const Text('Copy code'),
                                ),
                              ],
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              onSubmitted: (_) => _busy ? null : _confirm(),
                              decoration: const InputDecoration(
                                labelText: 'Activation code',
                                hintText: '123456',
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              StatusBanner(
                                ok: false,
                                title: 'Could not activate',
                                subtitle: _error!,
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _confirm,
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
                                  : const Text('Activate & continue'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : () => _issueCode(),
                              child: const Text('New code / open mail draft'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => AuthService.instance.signOut(),
                        child: const Text(
                          'Sign out',
                          style: TextStyle(color: EmColors.mutedForeground),
                        ),
                      ),
                    ],
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
