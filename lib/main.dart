import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/connection_screen.dart';
import 'screens/test_mode_screen.dart';

void main() {
  runApp(const PatikaApp());
}

class PatikaApp extends StatelessWidget {
  const PatikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patika Companion',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppState _appState;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    _appState.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ConnectionScreen(state: _appState),
      TestModeScreen(state: _appState),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Patika Companion')),
      body: screens[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Bağlantı'),
          NavigationDestination(icon: Icon(Icons.science), label: 'Test Modu'),
        ],
      ),
    );
  }
}
