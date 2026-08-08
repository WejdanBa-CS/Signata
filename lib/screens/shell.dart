import 'package:flutter/material.dart';

import '../widgets/em_widgets.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'image_tool_screen.dart';
import 'pdf_tool_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _historyKey = GlobalKey<HistoryScreenState>();

  void _openTab(int index) {
    setState(() => _index = index);
    if (index == 3) _historyKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const EmLogo()),
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onOpenTool: _openTab),
          const ImageToolScreen(),
          const PdfToolScreen(),
          HistoryScreen(key: _historyKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.waves_outlined),
            selectedIcon: Icon(Icons.waves),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: 'Image',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'PDF',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
