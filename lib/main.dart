import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/auth.dart';
import 'core/share_ingress.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'screens/verify_email_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  await AuthService.instance.initialize();
  ShareIngress.instance.start();
  runApp(const SignataApp());
}

class SignataApp extends StatelessWidget {
  const SignataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        final user = auth.user;
        final needsEmailVerify = auth.isSignedIn &&
            user != null &&
            user.provider == AuthProvider.email &&
            !user.emailVerified;

        return MaterialApp(
          title: 'Signata',
          debugShowCheckedModeBanner: false,
          theme: buildSignataTheme(),
          home: !auth.isReady
              ? const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFF57D9EC)),
                  ),
                )
              : !auth.isSignedIn
                  ? const LoginScreen()
                  : needsEmailVerify
                      ? const VerifyEmailScreen()
                      : const AppShell(),
        );
      },
    );
  }
}
