import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../widgets/em_widgets.dart';
import 'account_screen.dart';
import 'audio_tool_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'image_tool_screen.dart';
import 'pdf_tool_screen.dart';
import 'tools_hub_screen.dart';
import 'video_tool_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  EmTool? _activeTool;
  final _historyKey = GlobalKey<HistoryScreenState>();

  void _openTab(int index) {
    setState(() {
      _index = index;
      _activeTool = null;
    });
    if (index == 2) _historyKey.currentState?.refresh();
  }

  void _openTool(EmTool tool) {
    setState(() {
      _index = 1;
      _activeTool = tool;
    });
  }

  String get _defaultOwner =>
      AuthService.instance.user?.displayName ?? 'Studio Nova';

  Widget _toolScreen(EmTool tool) {
    switch (tool) {
      case EmTool.image:
        return ImageToolScreen(defaultOwner: _defaultOwner);
      case EmTool.audio:
        return AudioToolScreen(defaultOwner: _defaultOwner);
      case EmTool.video:
        return VideoToolScreen(defaultOwner: _defaultOwner);
      case EmTool.pdf:
        return PdfToolScreen(defaultOwner: _defaultOwner);
    }
  }

  String _toolTitle(EmTool tool) => switch (tool) {
        EmTool.image => 'Image',
        EmTool.audio => 'Audio',
        EmTool.video => 'Video',
        EmTool.pdf => 'PDF',
      };

  @override
  Widget build(BuildContext context) {
    final inTool = _activeTool != null;

    return Scaffold(
      appBar: AppBar(
        leading: inTool
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _activeTool = null),
              )
            : null,
        title: inTool
            ? Text(_toolTitle(_activeTool!),
                style: Theme.of(context).textTheme.titleLarge)
            : const EmLogo(),
      ),
      body: inTool
          ? _toolScreen(_activeTool!)
          : IndexedStack(
              index: _index,
              children: [
                HomeScreen(onOpenTool: _openTool),
                ToolsHubScreen(onOpenTool: _openTool),
                HistoryScreen(key: _historyKey),
                const AccountScreen(),
              ],
            ),
      bottomNavigationBar: inTool
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _openTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.waves_outlined),
                  selectedIcon: Icon(Icons.waves),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Tools',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Account',
                ),
              ],
            ),
    );
  }
}
