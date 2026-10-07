import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'accessibility/announcement_queue.dart';
import 'app_state.dart';
import 'l10n/strings_tr.dart';
import 'platform/app_version.dart';
import 'platform/launch_actions.dart';
import 'screens/connection_screen.dart';
import 'screens/listen_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/test_mode_screen.dart';
import 'settings/test_mode_access.dart';
import 'theme/app_theme.dart';
import 'theme/font_license.dart';
import 'voice/voice_controller.dart';
import 'widgets/sos_countdown_banner.dart';

void main() {
  registerFontLicense();
  runApp(const PatikaApp());
}

class PatikaApp extends StatelessWidget {
  /// Testler sahte TTS/titreşim ve kapalı otomatik başlatmayla bir
  /// AppState verebilsin diye; uygulamada null (varsayılan AppState).
  final AppState Function()? appStateFactory;

  /// Gizli Test Modu erişimi ve sürüm kaynağı; testler plugin gerektirmeyen
  /// sahteleri verir (null = gerçek, kalıcı olanlar).
  final TestModeAccess Function()? testModeFactory;
  final AppVersionSource? appVersion;

  const PatikaApp({super.key, this.appStateFactory, this.testModeFactory, this.appVersion});

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
      home: HomePage(
        appStateFactory: appStateFactory,
        testModeFactory: testModeFactory,
        appVersion: appVersion,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppState Function()? appStateFactory;
  final TestModeAccess Function()? testModeFactory;
  final AppVersionSource? appVersion;

  const HomePage({super.key, this.appStateFactory, this.testModeFactory, this.appVersion});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppState _appState;
  late final LaunchActions _launchActions;
  late final TestModeAccess _testMode;
  late final AppVersionSource _appVersion;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _appState = widget.appStateFactory?.call() ?? AppState();
    _appState.addListener(_onStateChanged);
    _appVersion = widget.appVersion ?? PackageInfoAppVersion();
    _testMode = widget.testModeFactory?.call() ?? TestModeAccess();
    _testMode.addListener(_onTestModeChanged);
    _loadTestMode();
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

  /// Kayıtlı durumu okur; Test Modu açık kalmışsa her açılışta sesli
  /// hatırlatır (kazara açılıp fark edilmeden kalmasın). Öncelik `low`:
  /// SOS geri sayımı, navigasyon ya da bağlantı duyurusunu kesmez,
  /// geciktirmez; sırada 10 sn'den fazla beklerse atılır.
  Future<void> _loadTestMode() async {
    await _testMode.load();
    if (!mounted) return;
    _testMode.remindOnLaunch(
      (text) => _appState.feedback
          .say(text, priority: AnnouncementPriority.low, dedupe: false),
      Tr.testModeReminder,
    );
  }

  /// Test Modu açılınca/gizlenince sekme listesi değişir. Gizlenirken o sekme
  /// seçiliyse Konuş'a dönülür (dizin listenin dışına taşmasın).
  void _onTestModeChanged() {
    if (!mounted) return;
    setState(() {
      if (_tabIndex >= _tabCount) _tabIndex = 0;
    });
  }

  int get _tabCount => _testMode.unlocked ? 4 : 3;

  @override
  void dispose() {
    _launchActions.detach();
    _appState.removeListener(_onStateChanged);
    _testMode.removeListener(_onTestModeChanged);
    _testMode.dispose();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ListenScreen(state: _appState),
      ConnectionScreen(state: _appState),
      SettingsScreen(
        store: _appState.settings,
        feedback: _appState.feedback,
        onStartTutorial: _appState.startTutorial,
        testMode: _testMode,
        version: _appVersion,
      ),
      // Gizli sekme EN SONDA: üç sekmenin sırası ve "Sekme N/M" etiketleri
      // açılışta değişmez, sekme belirince TalkBack odağı kaymaz.
      if (_testMode.unlocked)
        TestModeScreen(
          state: _appState,
          onHide: () {
            _testMode.hide();
            _appState.feedback.queue.stopAll();
            _appState.feedback.say(Tr.testModeHidden, dedupe: false);
          },
        ),
    ];

    // Acil durum geri sayımı/gönderimi sürerken SOS ekranı uygulamanın
    // TAMAMINI (alt çubuk dahil) kaplar ve arkadakini TalkBack'ten kapatır
    // (BlockSemantics, bkz. SosCountdownBanner). Boştayken hiçbir şey çizmez.
    return Stack(
      children: [
        _buildScaffold(screens),
        Positioned.fill(child: SosCountdownBanner(sos: _appState.sos)),
      ],
    );
  }

  Widget _buildScaffold(List<Widget> screens) {
    return Scaffold(
      // Üst çubuk yok: her ekran kendi başlığıyla başlar (EkranBasligi,
      // TalkBack'te ilk odak).
      body: SafeArea(bottom: false, child: screens[_tabIndex]),
      // Beyaz alt çubuk, üst köşeler yuvarlak, yukarı doğru yumuşak gölge.
      // NavigationBar korunuyor: "Sekme N / M" TalkBack etiketleri ondan.
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: PatikaTokens.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(PatikaTokens.radiusNav)),
          boxShadow: PatikaTokens.navShadow,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(PatikaTokens.radiusNav)),
          child: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.mic), label: Tr.tabListen),
              const NavigationDestination(icon: Icon(Icons.bluetooth), label: Tr.tabConnection),
              const NavigationDestination(icon: Icon(Icons.settings), label: Tr.tabSettings),
              if (_testMode.unlocked)
                const NavigationDestination(icon: Icon(Icons.science), label: Tr.tabTestMode),
            ],
          ),
        ),
      ),
    );
  }
}
