import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'l10n/strings_tr.dart';
import 'screens/connection_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/test_mode_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PatikaApp());
}

class PatikaApp extends StatelessWidget {
  const PatikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Tr.appTitle,
      theme: buildAppTheme(),
      // Material'in hazır erişilebilirlik metinleri ("Sekme 1/3", "Geri",
      // "seçili" vb.) Türkçe okunsun - yoksa TalkBack bunları İngilizce söyler.
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
      SettingsScreen(store: _appState.settings, feedback: _appState.feedback),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text(Tr.appTitle)),
      body: screens[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth), label: Tr.tabConnection),
          NavigationDestination(icon: Icon(Icons.science), label: Tr.tabTestMode),
          NavigationDestination(icon: Icon(Icons.settings), label: Tr.tabSettings),
        ],
      ),
    );
  }
}
