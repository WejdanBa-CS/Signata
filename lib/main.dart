import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const EchoMarkApp());
}

class EchoMarkApp extends StatelessWidget {
  const EchoMarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoMark',
      debugShowCheckedModeBanner: false,
      theme: buildEchoMarkTheme(),
      home: const AppShell(),
    );
  }
}
