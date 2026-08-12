/// Lightweight first-run checklist flags (per signed-in user).
library;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';

class OnboardingFlags {
  OnboardingFlags._();
  static final instance = OnboardingFlags._();

  static const _recoveryDismissed = 'signata_onboarding_recovery_dismissed';
  static const _recoveryExported = 'signata_onboarding_recovery_exported';
  static const _checklistDismissed = 'signata_onboarding_checklist_dismissed';
  static const _protectedOnce = 'signata_onboarding_protected_once';
  static const _tracedOnce = 'signata_onboarding_traced_once';

  String get _userSuffix {
    final id = AuthService.instance.user?.id ?? 'anonymous';
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _key(String base) => '${base}__$_userSuffix';

  Future<bool> shouldPromptRecoveryExport() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(_recoveryDismissed)) == true) return false;
    if (prefs.getBool(_recoveryDismissed) == true) return false;
    return true;
  }

  Future<void> markRecoveryHandled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_recoveryDismissed), true);
  }

  Future<void> markRecoveryExported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_recoveryExported), true);
    await prefs.setBool(_key(_recoveryDismissed), true);
  }

  Future<bool> shouldShowChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(_checklistDismissed)) == true) return false;
    final progress = await checklistProgress();
    return !(progress.recovery && progress.protected && progress.traced);
  }

  Future<({bool recovery, bool protected, bool traced})> checklistProgress() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      recovery: prefs.getBool(_key(_recoveryExported)) == true,
      protected: prefs.getBool(_key(_protectedOnce)) == true,
      traced: prefs.getBool(_key(_tracedOnce)) == true,
    );
  }

  Future<void> dismissChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_checklistDismissed), true);
  }

  Future<void> markProtectedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_protectedOnce), true);
  }

  Future<void> markTracedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_tracedOnce), true);
  }
}

/// Copies [text], then clears the clipboard after [delay] (best-effort).
Future<void> copySecretTemporarily(
  String text, {
  Duration delay = const Duration(seconds: 45),
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  Future<void>.delayed(delay, () async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}
