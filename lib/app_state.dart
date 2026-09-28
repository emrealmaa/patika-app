import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'commands/handlers/crossing_mode_handler.dart';
import 'commands/handlers/message_history_handler.dart';
import 'commands/handlers/navigation_handler.dart';
import 'commands/handlers/navigation_control_handler.dart';
import 'commands/handlers/number_handler.dart';
import 'commands/handlers/control_handler.dart';
import 'commands/handlers/settings_handler.dart';
import 'commands/incoming_message_log.dart';
import 'commands/intent.dart';
import 'commands/log_entry.dart';
import 'commands/sent_messages.dart';
import 'commands/url_opener.dart';
import 'commands/voice_intent_classifier.dart';
import 'contacts/alias_store.dart';
import 'l10n/strings_tr.dart';
import 'l10n/turkish_suffix.dart';
import 'navigation/app_identity.dart';
import 'navigation/google_client.dart';
import 'navigation/maps_config.dart';
import 'navigation/navigation_backend.dart';
import 'navigation/navigation_session.dart';
import 'navigation/place_search.dart';
import 'navigation/route_planner.dart';
import 'permissions/location_access.dart';
import 'permissions/permission_explainer.dart';
import 'platform/call_service.dart';
import 'platform/direct_actions.dart';
import 'platform/incoming_messages.dart';
import 'platform/location_service.dart';
import 'platform/notification_access.dart';
import 'platform/simulated_call_service.dart';
import 'settings/settings_store.dart';
import 'sos/emergency_contacts.dart';
import 'sos/emergency_number.dart';
import 'sos/feedback_sos_announcer.dart';
import 'sos/sos_call_monitor.dart';
import 'sos/sos_config.dart';
import 'sos/sos_controller.dart';
import 'sos/sos_delivery.dart';
import 'sos/sos_permissions.dart';
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

  /// Telefonun kendi gelen arama durumu (Faz 4b) - BLE'den bağımsız, bkz.
  /// `lib/platform/call_service.dart`. Gerçek `NotificationListenerService`
  /// gelene kadar hep [SimulatedCallService].
  late final PatikaCallService callService;

  /// Sesli navigasyon (Faz 6): rota + konum + duyurular. Konum kaynağı
  /// varsayılan olarak gerçek (`geolocator`); Test Modu kendi simülasyon
  /// kaynağını `NavigationSession.start(location: ...)` ile verir.
  late final PatikaLocationService locationService;
  late final LocationAccess locationAccess;
  late final NavigationSession navigation;

  /// Acil durum (SOS, Faz 7): geri sayım, acil kişilere SMS + tek arama.
  /// Yalnızca `direct` derlemesinde gönderir; `play`'de "desteklenmiyor" der.
  late final SosController sos;
  late final EmergencyContactStore emergencyContacts;

  /// Test Modu'nun navigasyon simülasyonu için: yalnızca simülasyon
  /// oturumları bunu kullanır, gerçek konum akmaz.
  final simulatedLocation = SimulatedLocationService();

  /// Bildirim dinleyici erişim durumu/ayar ekranı (Faz 4b, iskelet -
  /// gerçek dinleyici henüz yok). Test Modu'ndan denenebiliyor.
  late final NotificationAccess notificationAccess;

  /// Bildirimden yakalanan mesajlar (varsayılan SMS + WhatsApp, bkz.
  /// PatikaNotificationListener.kt) ve "yüksek sesle okunuyor" uyarısının
  /// bir kez gösterilip gösterilmediği.
  late final IncomingMessages incomingMessages;
  late final LoudMessagesNotice loudMessagesNotice;

  /// Bildirimden yakalanan mesajların bellekteki günlüğü - "mesajlarımı
  /// oku"/"son bildirimleri oku" bunu okuyor, [CommandRouter]'la paylaşılıyor.
  final _messageLog = IncomingMessageLog();

  BleConnectionState connectionState = BleConnectionState.disconnected;
  List<DiscoveredDevice> devices = [];
  final List<LogEntry> log = [];

  /// Gözlüğün bildirdiği son pil yüzdesi (bağlı değilken null).
  int? glassesBattery;

  /// Gözlükten gelen son buton/jest olayı (test ekranında gösteriliyor).
  String? lastGlassesEvent;

  /// Şu an çalmakta olan gelen arama (yokken null). Gözlük butonunun
  /// dokunma/uzun basış davranışını değiştirir (bkz. [_onButton]).
  IncomingCall? _ringingCall;

  final List<StreamSubscription> _subs = [];

  /// BLE'den ayrı: `toggleMode`'daki [_detach]/[_attach] döngüsü bunu
  /// kapatıp yeniden açmamalı, [callService] BLE moduyla değişmiyor.
  StreamSubscription? _callSub;

  /// Aynı gerekçeyle BLE _detach/_attach döngüsünden ayrı tutuluyor.
  StreamSubscription? _messageSub;

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
    PatikaCallService? callService,
    NotificationAccess? notificationAccess,
    IncomingMessages? incomingMessages,
    LoudMessagesNotice? loudMessagesNotice,
    PatikaLocationService? locationService,
    LocationAccess? locationAccess,
    MapsConfig? mapsConfig,
    RoutePlanner? routePlanner,
    PlaceSearch? placeSearch,
    bool Function()? isAppVisible,
    EmergencyContactStore? emergencyContacts,
    SosDelivery? sosDelivery,
    SosPermissions? sosPermissions,
    EmergencyNumber? emergencyNumber,
    SosCallMonitor? sosCallMonitor,
    bool autoStart = true,
  })  : settings = settings ?? SettingsStore(),
        _speech = speech ?? FlutterTtsOutput(),
        _background = background ?? BackgroundService(),
        _deviceMemory = deviceMemory ??
            ((simulated) => SharedPrefsDeviceMemory(simulated: simulated)) {
    feedback = FeedbackHub(
      queue: AnnouncementQueue(_speech),
      // Gözlükte titreşim motoru yok; titreşim yalnızca telefonda.
      haptics: haptics ?? PhoneHaptics(),
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
    // Sesli navigasyon (Faz 6). Konum izni melez akışla istenir: eğitimin
    // sonunda (bkz. [_offerLocationAfterTutorial]); reddeden/atlayan için
    // ilk navigasyonda, uygulama ön plandaysa (bkz. NavigationSession.start).
    this.locationService = locationService ?? GeolocatorLocationService();
    this.locationAccess = locationAccess ??
        PermissionLocationAccess(permissions, onGranted: _background.ensureLocationType);
    // Google Routes/Places yalnızca `--dart-define=PATIKA_MAPS_API_KEY=...`
    // ile derlendiyse kurulur (bkz. MapsConfig); yoksa navigasyon Google
    // Haritalar uygulamasına düşen yedek akışla çalışır.
    final maps = mapsConfig ?? const MapsConfig();
    // Anahtar Android uygulama kısıtlamalıysa (paket + SHA-1) istekler
    // X-Android-Package / X-Android-Cert başlıklarını taşımalı.
    final identity = MethodChannelAppIdentity();
    final planner = routePlanner ??
        (maps.hasKey ? GoogleRoutePlanner(apiKey: maps.apiKey, identity: identity) : null);
    final places = placeSearch ??
        (maps.hasKey ? GooglePlaceSearch(apiKey: maps.apiKey, identity: identity) : null);
    navigation = NavigationSession(
      feedback: feedback,
      location: this.locationService,
      planner: planner,
      access: this.locationAccess,
      isAppVisible: isAppVisible ?? _appIsVisible,
    );
    final navigationBackend = NavigationBackend(
      session: navigation,
      planner: planner,
      places: places,
      openMaps: openUrl ?? _openMapsApp,
    );

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
      messageHistory: MessageHistoryHandler(_messageLog),
      number: NumberHandler(contacts: resolver),
      alias: AliasHandler(contacts: resolver),
      settings: SettingsHandler(this.settings),
      control: ControlHandler(this),
      navigation: NavigationHandler(dialogs: dialogs, backend: navigationBackend),
      navigationControl: NavigationControlHandler(navigation),
      crossingMode: CrossingModeHandler(navigation),
    );
    tutorial = Tutorial(
      feedback,
      tutorialProgress ?? SharedPrefsTutorialProgress(),
      onFirstRunCompleted: _offerLocationAfterTutorial,
    );
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

    // Acil durum (Faz 7). Konum geri sayım başlarken aranır; izinler acil kişi
    // kurulumunda istenir, burada yalnızca yoklanır.
    this.emergencyContacts = emergencyContacts ?? SharedPrefsEmergencyContactStore();
    sos = SosController(
      delivery: sosDelivery ??
          DirectSosDelivery(
            direct: directActions,
            contacts: this.emergencyContacts,
            permissions: sosPermissions ?? const PermissionHandlerSosPermissions(),
            emergency: emergencyNumber ?? const EmergencyNumber.fromDefines(),
          ),
      announcer: FeedbackSosAnnouncer(feedback, ensureListening: _ensureSosListening),
      getLocation: () => this.locationService.currentPosition(),
      hasLocationPermission: () => this.locationAccess.isGranted(),
      call112Enabled: () => this.settings.value.emergencyCall112,
      callMonitor: sosCallMonitor ?? const FixedDelayCallMonitor(),
    );
    sos.status.addListener(notifyListeners);
    voice.onSosSpeech = _onSosSpeech;

    this.settings.addListener(_applySettings);
    this.settings.load();
    _applySettings();

    this.callService = callService ?? SimulatedCallService();
    _callSub = this.callService.incomingCall.listen(_onIncomingCall);
    this.notificationAccess = notificationAccess ?? MethodChannelNotificationAccess();
    this.incomingMessages = incomingMessages ?? MethodChannelIncomingMessages();
    this.loudMessagesNotice = loudMessagesNotice ?? SharedPrefsLoudMessagesNotice();
    _messageSub = this.incomingMessages.messages.listen(_onIncomingMessage);

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

  /// Eğitimin sonunda: konum izni yoksa sesli açıklamayla ister. Ekran açık,
  /// kullanıcı başında; izin verilirse arka plan servisi konum türüyle
  /// yeniden başlar. Verilmezse ilk navigasyonda yeniden denenir.
  Future<void> _offerLocationAfterTutorial() async {
    if (await locationAccess.isGranted()) return;
    await locationAccess.requestWithExplanation();
  }

  /// Google Haritalar yedeği: yüklü haritayı (yoksa tarayıcıyı) açar.
  static Future<bool> _openMapsApp(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Uygulama şu an ön planda mı? Ekran kapalıyken/arka planda (ör.
  /// kulaklıktan sesle başlatma) izin penceresi görünmez ve konum türlü servis
  /// başlatılamaz; bilinmiyorsa (null) güvenli tarafta kalıp "ön planda değil" denir.
  static bool _appIsVisible() {
    try {
      return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }

  void _applySettings() {
    final s = settings.value;
    _speech.configure(rate: s.speechRate, pitch: s.pitch);
    notifyListeners();
  }

  /// Sadece simülasyon modunda dolu - test ekranı olay enjekte etmek için.
  SimulatedBleService? get simulator =>
      isSimulated ? bleService as SimulatedBleService : null;

  /// Gerçek `PatikaNotificationListener.kt` gelene kadar hep dolu - test
  /// ekranı gelen aramayı buradan tetikler.
  SimulatedCallService? get callSimulator =>
      callService is SimulatedCallService ? callService as SimulatedCallService : null;

  /// Test ekranında ve gözlük buton mantığında gösterilecek/kullanılacak.
  IncomingCall? get ringingCall => _ringingCall;

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
  /// son duyuruyu tekrarlar (karşıya geçiş duraklamasındayken navigasyonu
  /// devam ettirir), uzun basış acil durum (SOS) geri sayımını başlatır.
  /// Telefon çalarken (bkz. [_ringingCall]) dokunma/uzun basış anlamı
  /// değişir: dokunma açar, uzun basış reddeder - SOS o sırada yalnızca
  /// sesle erişilebilir (bkz. CLAUDE.md Faz 4b kararları).
  ///
  /// SOS sürerken dokunuşlar ÖNCE SOS'a bakar: geri sayımda tek/çift dokunuş
  /// iptaldir; "112 için çift dokunun" penceresinde çift dokunuş 112 onayıdır
  /// ("tekrar et" değil).
  void _onButton(GlassesButton button) {
    lastGlassesEvent = _buttonName(button);
    if (_onSosButton(button)) {
      notifyListeners();
      return;
    }
    final ringing = _ringingCall;
    switch (button) {
      case GlassesButton.tap:
        if (ringing != null) {
          callService.answer();
          feedback.signal(FeedbackEvent.success, text: Tr.callAnswered(ringing.callerName));
        } else {
          // Karşıya geçiş duraklamasında da dinler: SOS ve sesli komutlar
          // kavşakta erişilebilir kalmalı (duraklama çıkışı çift dokunuşta).
          voice.startListening(ListenSource.glasses);
        }
      case GlassesButton.doubleTap:
        if (navigation.isPausedForCrossing) {
          // Karşıya geçiş duraklaması: çift dokunuş "karşıya ulaştım" demektir
          // (dört çıkış kanalından biri); "son duyuruyu tekrarla" anlamı o
          // sırada geri planda kalır (sesle "tekrar et" yine çalışır).
          navigation.resumeFromCrossing();
        } else if (!repeatLast()) {
          feedback.signal(FeedbackEvent.error, text: Tr.nothingToRepeat);
        }
      case GlassesButton.longPress:
        if (ringing != null) {
          callService.reject();
          feedback.signal(FeedbackEvent.success, text: Tr.callRejected(ringing.callerName));
        } else {
          _startSos(SosSource.glasses);
        }
    }
    notifyListeners();
  }

  /// SOS'u başlatır ve işlem geçmişine (yalnızca kayıt, ses/titreşim yok:
  /// SOS kendi geri bildirimini verir) yazar.
  void _startSos(SosSource source) {
    _addLog(PatikaIntent.sos, null, ActionResult.silentOk('SOS'));
    notifyListeners();
    unawaited(sos.trigger(source));
  }

  /// SOS sürerken dokunuşu SOS'a yorar; yorduysa true.
  bool _onSosButton(GlassesButton button) {
    final touch = button == GlassesButton.tap || button == GlassesButton.doubleTap;
    if (sos.offering112 && button == GlassesButton.doubleTap) {
      unawaited(sos.confirm112());
      return true;
    }
    if (sos.inCountdown && touch) {
      sos.cancel(SosCancelSource.glasses);
      return true;
    }
    // Gönderim başladı, iptal artık mümkün değil: bunu söyle (sessiz kalma).
    // 112 penceresindeki tek dokunuş yine dinletir ("yardım" vb.).
    if (sos.phase == SosPhase.sending && !sos.offering112 && touch) {
      sos.cancel(SosCancelSource.glasses);
      return true;
    }
    return false;
  }

  /// Geri sayım tiki mikrofonu "iptal" için açık tutar.
  void _ensureSosListening() {
    if (sos.inCountdown) voice.listenForSos();
  }

  /// Geri sayımda tanınan konuşma: yalnızca iptal / hemen gönder.
  void _onSosSpeech(String text) {
    switch (classifySosVoice(text)) {
      case SosVoiceCommand.cancel:
        sos.cancel(SosCancelSource.voice);
      case SosVoiceCommand.sendNow:
        sos.sendNow();
      case null:
        break;
    }
  }

  /// Gelen arama başladığında/bittiğinde: [_ringingCall] güncellenir, çalmaya
  /// başlarken yüksek öncelikle "$ad arıyor" duyurulur (bkz. §4b/2).
  void _onIncomingCall(IncomingCall? call) {
    _ringingCall = call;
    if (call != null) {
      feedback.signal(FeedbackEvent.incomingCall,
          text: Tr.incomingCall(call.callerName), priority: AnnouncementPriority.high);
    }
    notifyListeners();
  }

  /// Bildirimden yakalanan yeni mesaj (bkz. §4b/3). Günlüğe (bkz.
  /// [_messageLog]) susturulmuş olsa bile eklenir - "bildirimleri sustur"
  /// yalnızca duyuruyu engeller, "mesajlarımı oku" ile yine okunabilir.
  /// Susturulmamışsa: ayar açıksa içerik okunur - ilk kez okunurken önce
  /// bir kerelik sesli gizlilik uyarısı verilir; kapalıysa yalnızca kimden
  /// geldiği söylenir.
  Future<void> _onIncomingMessage(IncomingMessage message) async {
    _messageLog.add(message);
    if (settings.value.notificationsMuted) return;

    final senderAblative = ablative(message.senderName);
    if (!settings.value.readMessagesAloud) {
      feedback.signal(FeedbackEvent.incomingMessage,
          text: Tr.incomingMessageSenderOnly(senderAblative),
          priority: AnnouncementPriority.high);
      return;
    }
    if (!await loudMessagesNotice.wasShown()) {
      await feedback.say(Tr.loudMessagesNotice);
      await loudMessagesNotice.markShown();
    }
    feedback.signal(FeedbackEvent.incomingMessage,
        text: Tr.incomingMessage(senderAblative, message.body),
        priority: AnnouncementPriority.high);
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

  @override
  void triggerSos() => _startSos(SosSource.voice);

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

  void _addLog(PatikaIntent intent, String? entity, ActionResult result) {
    log.insert(
      0,
      LogEntry(time: DateTime.now(), intent: intent, entity: entity, result: result),
    );
    if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);
  }

  void _record(PatikaIntent intent, String? entity, ActionResult result) {
    _addLog(intent, entity, result);
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
    sos.status.removeListener(notifyListeners);
    sos.dispose();
    voice.dispose();
    tutorial.dispose();
    dialogs.cancel(null);
    dialogs.dispose();
    settings.removeListener(_applySettings);
    feedback.queue.stopAll();
    feedback.updateObstacle(null);
    a11y.attachFeedbackHub(null);
    _detach();
    _callSub?.cancel();
    callService.dispose();
    _messageSub?.cancel();
    incomingMessages.dispose();
    navigation.dispose();
    locationService.dispose();
    simulatedLocation.dispose();
    _background.stop();
    super.dispose();
  }
}
