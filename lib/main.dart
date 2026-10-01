import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'l10n/strings_tr.dart';
import 'platform/launch_actions.dart';
import 'screens/connection_screen.dart';
import 'screens/listen_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/test_mode_screen.dart';
import 'theme/app_theme.dart';
import 'voice/voice_controller.dart';
import 'widgets/sos_countdown_banner.dart';

void main() {
  runApp(const PatikaApp());
}

class PatikaApp extends StatelessWidget {
  /// Testler sahte TTS/titreşim ve kapalı otomatik başlatmayla bir
  /// AppState verebilsin diye; uygulamada null (varsayılan AppState).
  final AppState Function()? appStateFactory;

  const PatikaApp({super.key, this.appStateFactory});

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
      home: HomePage(appStateFactory: appStateFactory),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppState Function()? appStateFactory;

  const HomePage({super.key, this.appStateFactory});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppState _appState;
  late final LaunchActions _launchActions;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _appState = widget.appStateFactory?.call() ?? AppState();
    _appState.addListener(_onStateChanged);
    // Hızlı Ayarlar karosu: "Konuş" sekmesine geç ve dinlemeyi başlat.
    _launchActions = LaunchActions(onListen: () {
      setState(() => _tabIndex = 0);
      if (!_appState.voice.isActive) {
        _appState.voice.startListening(ListenSource.tile);
      }
    })
      ..attach();
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _launchActions.detach();
    _appState.removeListener(_onStateChanged);
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ListenScreen(state: _appState),
      ConnectionScreen(state: _appState),
      TestModeScreen(state: _appState),
      SettingsScreen(
        store: _appState.settings,
        feedback: _appState.feedback,
        onStartTutorial: _appState.startTutorial,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text(Tr.appTitle)),
      // Acil durum geri sayımı her sekmenin üstünde görünür (iptal düğmesi).
      body: Column(
        children: [
          SosCountdownBanner(sos: _appState.sos),
          Expanded(child: screens[_tabIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic), label: Tr.tabListen),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: Tr.tabConnection),
          NavigationDestination(icon: Icon(Icons.science), label: Tr.tabTestMode),
          NavigationDestination(icon: Icon(Icons.settings), label: Tr.tabSettings),
        ],
      ),
    );
  }
}
