import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'accessibility/a11y_announcer.dart' as a11y;
import 'accessibility/announcement_queue.dart';
import 'accessibility/earcons.dart';
import 'accessibility/feedback_hub.dart';
import 'accessibility/haptic_patterns.dart';
import 'accessibility/speech_output.dart';
import 'background/foreground_service.dart';
import 'ble/ble_command.dart';
import 'ble/ble_connection_state.dart';
import 'ble/connection_supervisor.dart';
import 'ble/device_memory.dart';
import 'ble/glasses_haptics.dart';
import 'ble/glasses_protocol.dart';
import 'ble/patika_ble_service.dart';
import 'ble/real_ble_service.dart';
import 'ble/simulated_ble_service.dart';
import 'commands/action_result.dart';
import 'commands/command_router.dart';
import 'commands/contact_resolver.dart';
import 'commands/handlers/alias_handler.dart';
import 'commands/handlers/call_handler.dart';
import 'commands/handlers/message_handler.dart';
import 'commands/handlers/number_handler.dart';
import 'commands/handlers/control_handler.dart';
import 'commands/handlers/settings_handler.dart';
import 'commands/intent.dart';
import 'commands/log_entry.dart';
import 'commands/sent_messages.dart';
import 'commands/url_opener.dart';
import 'contacts/alias_store.dart';
import 'l10n/strings_tr.dart';
import 'permissions/permission_explainer.dart';
import 'platform/direct_actions.dart';
import 'settings/settings_store.dart';
import 'tutorial/tutorial.dart';
import 'voice/dialog_manager.dart';
import 'voice/speech_input_service.dart';
import 'voice/voice_controller.dart';

/// Uygulamanın tek merkezi durumu. BLE servisi (gerçek/simüle), bağlantı
/// denetçisi, komut yönlendirici ve geri bildirim merkezini birbirine
/// bağlar; ekranlar sadece bunu dinler - hangi BLE implementasyonunun aktif
/// olduğunu bilmeleri gerekmez.
///
/// Donanım henüz olmadığı için varsayılan mod SİMÜLASYON - gerçek moda
/// geçmek (RealBleService) ekrandaki bir switch ile mümkün, ama gerçek
/// donanım gelene kadar cihaz bulunamayacaktır (beklenen davranış).
class AppState extends ChangeNotifier implements ControlActions {
  /// İşlem geçmişi bu kadar kayıtla sınırlı (bellek sınırsız büyümesin).
  static const maxLogEntries = 100;

  final SettingsStore settings;
  final SpeechOutput _speech;
  final BackgroundService _background;
  final DeviceMemory Function(bool simulated) _deviceMemory;
  late final FeedbackHub feedback;
  late final CommandRouter router;
  late final PermissionExplainer permissions;
  late final VoiceController voice;
  late final DialogManager dialogs;
  late final Tutorial tutorial;

  late PatikaBleService bleService;
  late ConnectionSupervisor _supervisor;
  bool isSimulated = true;

  BleConnectionState connectionState = BleConnectionState.disconnected;
  List<DiscoveredDevice> devices = [];
  final List<LogEntry> log = [];

  /// Gözlüğün bildirdiği son pil yüzdesi (bağlı değilken null).
  int? glassesBattery;

  /// Gözlükten gelen son buton/jest olayı (test ekranında gösteriliyor).
  String? lastGlassesEvent;

  final List<StreamSubscription> _subs = [];

  /// Parametreler testlerde sahte uygulamalar vermek için; uygulamada
  /// hepsi gerçek platform uygulamalarına düşer. [autoStart] kapalıyken
  /// açılıştaki izin/arka plan servisi/otomatik bağlanma adımı atlanır.
  AppState({
    SettingsStore? settings,
    SpeechOutput? speech,
    HapticOutput? haptics,
    EarconPlayer? earcons,
    BackgroundService? background,
    DeviceMemory Function(bool simulated)? deviceMemory,
    SpeechInput? speechInput,
    Future<bool> Function()? ensureMicPermission,
    TutorialProgress? tutorialProgress,
    ContactResolver? contacts,
    UrlOpener? openUrl,
    DirectActions? direct,
    Future<bool> Function()? ensureCallPermission,
    Future<bool> Function()? ensureSmsPermission,
    bool autoStart = true,
  })  : settings = settings ?? SettingsStore(),
        _speech = speech ?? FlutterTtsOutput(),
        _background = background ?? BackgroundService(),
        _deviceMemory = deviceMemory ??
            ((simulated) => SharedPrefsDeviceMemory(simulated: simulated)) {
    feedback = FeedbackHub(
      queue: AnnouncementQueue(_speech),
      // Desenler hem telefonda hem (bağlıysa) gözlükte çalar.
      haptics: CompositeHaptics([
        haptics ?? PhoneHaptics(),
        GlassesHaptics(() => bleService),
      ]),
      earcons: earcons ?? AudioplayersEarconPlayer(),
      settings: () => this.settings.value,
    );
    a11y.attachFeedbackHub(feedback);
    permissions = PermissionExplainer(feedback);
    // Tüm kişi işlemleri (ARA/MESAJ/NUMARA/TAKMA_AD) aynı çözücüyü
    // paylaşıyor: rehber önbelleği ve takma adlar ortak; rehber izni sesli
    // açıklamayla isteniyor.
    final resolver = contacts ??
        ContactResolver(
          aliases: SharedPrefsAliasStore(),
          ensurePermission: () =>
              permissions.ensure(Permission.contacts, Tr.contactsPermissionWhy),
        );
    // Çok adımlı sesli akışlar (ARA, MESAJ): soru bitince dinlemeyi kendisi
    // açar; bitince sonuç işlem geçmişine yazılıp duyurulur.
    dialogs = DialogManager(
      feedback: feedback,
      listen: ({required bool dictation}) => voice.listenForReply(dictation: dictation),
      onFinished: _onDialogFinished,
    );
    // Doğrudan arama/SMS yalnızca "direct" derleme türünde; izinler ilk
    // kullanımda sesli açıklamayla isteniyor.
    final directActions = direct ?? MethodChannelDirectActions();
    final sentMessages = SentMessageLog();
    router = CommandRouter(
      call: CallHandler(
        contacts: resolver,
        dialogs: dialogs,
        openUrl: openUrl,
        direct: directActions,
        ensureCallPermission: ensureCallPermission ??
            () => permissions.ensure(Permission.phone, Tr.callPermissionWhy),
      ),
      message: MessageHandler(
        contacts: resolver,
        dialogs: dialogs,
        openUrl: openUrl,
        direct: directActions,
        ensureSmsPermission: ensureSmsPermission ??
            () => permissions.ensure(Permission.sms, Tr.smsPermissionWhy),
        sent: sentMessages,
      ),
      lastMessage: LastMessageHandler(sentMessages),
      number: NumberHandler(contacts: resolver),
      alias: AliasHandler(contacts: resolver),
      settings: SettingsHandler(this.settings),
      control: ControlHandler(this),
    );
    tutorial = Tutorial(feedback, tutorialProgress ?? SharedPrefsTutorialProgress());
    voice = VoiceController(
      speech: speechInput ?? SpeechInputService(),
      feedback: feedback,
      ensureMicPermission: ensureMicPermission ??
          () => permissions.ensure(Permission.microphone, Tr.micPermissionWhy),
      submit: _process,
      // Dinleme başlayınca süren eğitim de susar (tetikleyiciyle araya girme).
      onListenStart: tutorial.stop,
      onMicrophoneGranted: _background.ensureMicrophoneType,
    )..dialog = dialogs;
    this.settings.addListener(_applySettings);
    this.settings.load();
    _applySettings();

    _attach(SimulatedBleService());
    if (autoStart) start();
  }

  /// Açılış: bildirim izni (arka plan servisi için) -> arka plan servisi ->
  /// son gözlüğe otomatik bağlanma -> (ilk açılışsa) sesli eğitim.
  Future<void> start() async {
    await permissions.ensure(Permission.notification, Tr.notificationPermissionWhy);
    await _background.start(_notificationText);
    await _supervisor.start();
    await tutorial.startIfFirstRun();
  }

  void _applySettings() {
    final s = settings.value;
    _speech.configure(rate: s.speechRate, pitch: s.pitch);
    notifyListeners();
  }

  /// Sadece simülasyon modunda dolu - test ekranı olay enjekte etmek için.
  SimulatedBleService? get simulator =>
      isSimulated ? bleService as SimulatedBleService : null;

  bool get isHealthy => _supervisor.isHealthy;

  void _attach(PatikaBleService service) {
    bleService = service;
    _supervisor = ConnectionSupervisor(
      service,
      _deviceMemory(isSimulated),
      onHealthy: () {
        feedback.signal(FeedbackEvent.connected,
            text: Tr.glassesConnected, priority: AnnouncementPriority.high);
        _refresh();
      },
      onLost: () {
        feedback.signal(FeedbackEvent.disconnected,
            text: Tr.glassesDisconnected, priority: AnnouncementPriority.high);
        _refresh();
      },
      onPersistentFailure: () {
        feedback.signal(FeedbackEvent.error,
            text: Tr.cannotReachGlasses, priority: AnnouncementPriority.high);
      },
    );
    _subs
      ..add(service.connectionState.listen((state) {
        connectionState = state;
        if (state != BleConnectionState.connected) glassesBattery = null;
        _refresh();
      }))
      ..add(service.discoveredDevices.listen((found) {
        devices = found;
        notifyListeners();
      }))
      ..add(service.commands.listen(_process))
      ..add(service.batteryLevel.listen((percent) {
        glassesBattery = percent;
        notifyListeners();
      }))
      ..add(service.buttonEvents.listen(_onButton))
      ..add(service.gestureEvents.listen(_onGesture));
  }

  Future<void> _detach() async {
    _supervisor.dispose();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    bleService.dispose();
  }

  void _refresh() {
    _background.update(_notificationText);
    notifyListeners();
  }

  String get _notificationText {
    if (connectionState == BleConnectionState.connected && _supervisor.isHealthy) {
      return Tr.notificationConnected;
    }
    if (connectionState == BleConnectionState.disconnected && !_supervisor.isReconnecting) {
      return Tr.notificationDisconnected;
    }
    return Tr.notificationSearching;
  }

  /// Gözlük butonu: tek dokunuş dinler (dinlerken iptal eder), çift dokunuş
  /// son duyuruyu tekrarlar, uzun basış SOS (Faz 7'ye kadar yer tutucu).
  void _onButton(GlassesButton button) {
    lastGlassesEvent = _buttonName(button);
    switch (button) {
      case GlassesButton.tap:
        voice.startListening(ListenSource.glasses);
      case GlassesButton.doubleTap:
        if (!repeatLast()) feedback.signal(FeedbackEvent.error, text: Tr.nothingToRepeat);
      case GlassesButton.longPress:
        feedback.signal(FeedbackEvent.error,
            text: Tr.sosNotReady, priority: AnnouncementPriority.high);
    }
    notifyListeners();
  }

  /// Çift baş sallama yalnızca ayar açıksa dinlemeyi başlatır (yanlışlıkla
  /// tetiklenebildiği için varsayılan kapalı); kapalıyken sessizce yok sayılır.
  void _onGesture(GlassesGesture gesture) {
    lastGlassesEvent = _gestureName(gesture);
    if (gesture == GlassesGesture.doubleNod && settings.value.nodToListen) {
      voice.startListening(ListenSource.gesture);
    }
    notifyListeners();
  }

  // --- ControlActions (DUR / TEKRAR / EĞİTİM komutları) ---------------------

  @override
  void stopEverything() {
    tutorial.stop();
    voice.cancel();
    dialogs.cancel(null);
    feedback.queue.stopAll();
  }

  @override
  bool repeatLast() => feedback.queue.repeatLast();

  @override
  void startTutorial() => tutorial.start();

  static String _buttonName(GlassesButton b) => switch (b) {
        GlassesButton.tap => Tr.buttonTap,
        GlassesButton.doubleTap => Tr.buttonDoubleTap,
        GlassesButton.longPress => Tr.buttonLongPress,
      };

  static String _gestureName(GlassesGesture g) => switch (g) {
        GlassesGesture.doubleNod => Tr.gestureDoubleNod,
      };

  /// Kaynağı ne olursa olsun (gözlük BLE'si, simülasyon, telefon mikrofonu)
  /// her komutun geçtiği tek yol: route -> log -> sesli sonuç.
  Future<void> _process(BleCommand command) async {
    final result = await router.route(command);
    // İş bir diyaloğa devredildiyse sonuç diyalog bitince gelecek.
    if (result.handedOff) return;
    _record(command.intent, command.entity, result);
  }

  void _onDialogFinished(DialogFlow flow, ActionResult result) =>
      _record(flow.intent, flow.entityLabel, result);

  void _record(PatikaIntent intent, String? entity, ActionResult result) {
    log.insert(
      0,
      LogEntry(time: DateTime.now(), intent: intent, entity: entity, result: result),
    );
    if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);
    // Sonuç hem sesle hem titreşimle (+ kısa sesle) bildiriliyor; uzun
    // ayrıntı modunda sonucun açıklaması da okunuyor.
    feedback.result(result);
    notifyListeners();
  }

  /// Simülasyon <-> gerçek BLE arasında geçiş yapar. Mevcut servis dispose
  /// edilip yenisi kurulur, log geçmişi korunur; yeni modda da son cihaza
  /// otomatik bağlanma denenir.
  Future<void> toggleMode(bool simulated) async {
    if (simulated == isSimulated) return;
    await _detach();

    isSimulated = simulated;
    devices = [];
    glassesBattery = null;
    connectionState = BleConnectionState.disconnected;
    _attach(simulated
        ? SimulatedBleService()
        : RealBleService(permissions: permissions));
    _refresh();
    await _supervisor.start();
  }

  Future<void> startScan() => bleService.startScan();

  void connect(String deviceId) => _supervisor.connect(deviceId);

  void disconnect() {
    _supervisor.disconnect();
    feedback.signal(FeedbackEvent.disconnected, text: Tr.glassesDisconnectedByUser);
  }

  /// Sadece simülasyon modundayken anlamlı - test ekranındaki butonlar bunu
  /// çağırır.
  void injectTestCommand(String intentRaw, {String? entity}) =>
      simulator?.injectCommand(intentRaw, entity: entity);

  /// Telefonun kendi mikrofonundan tanınan komut. BLE servisinden bağımsız
  /// olduğu için hem simülasyon hem gerçek modda çalışır - gözlük donanımı
  /// gerekmez.
  Future<void> submitVoiceCommand(BleCommand command) => _process(command);

  @override
  void dispose() {
    voice.dispose();
    tutorial.dispose();
    dialogs.cancel(null);
    dialogs.dispose();
    settings.removeListener(_applySettings);
    feedback.queue.stopAll();
    feedback.updateObstacle(null);
    a11y.attachFeedbackHub(null);
    _detach();
    _background.stop();
    super.dispose();
  }
}
