import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/auth.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
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
  runApp(const EchoMarkApp());
}

class EchoMarkApp extends StatelessWidget {
  const EchoMarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        return MaterialApp(
          title: 'EchoMark',
          debugShowCheckedModeBanner: false,
          theme: buildEchoMarkTheme(),
          home: !auth.isReady
              ? const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFF57D9EC)),
                  ),
                )
              : auth.isSignedIn
                  ? const AppShell()
                  : const LoginScreen(),
        );
      },
    );
  }
}
