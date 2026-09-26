import 'dart:async';

import 'package:flutter/foundation.dart';

import 'accessibility/a11y_announcer.dart' as a11y;
import 'accessibility/announcement_queue.dart';
import 'accessibility/earcons.dart';
import 'accessibility/feedback_hub.dart';
import 'accessibility/haptic_patterns.dart';
import 'accessibility/speech_output.dart';
import 'ble/ble_command.dart';
import 'ble/ble_connection_state.dart';
import 'ble/patika_ble_service.dart';
import 'ble/real_ble_service.dart';
import 'ble/simulated_ble_service.dart';
import 'commands/command_router.dart';
import 'commands/handlers/settings_handler.dart';
import 'commands/log_entry.dart';
import 'l10n/strings_tr.dart';
import 'settings/settings_store.dart';

/// Uygulamanın tek merkezi durumu. BLE servisi (gerçek/simüle) ile komut
/// yönlendiriciyi (CommandRouter) birbirine bağlar, ekranlar (ConnectionScreen/
/// TestModeScreen) sadece bunu dinler - hangi BLE implementasyonunun aktif
/// olduğunu bilmeleri gerekmez.
///
/// Donanım henüz olmadığı için varsayılan mod SİMÜLASYON - gerçek moda
/// geçmek (RealBleService) ekrandaki bir switch ile mümkün, ama gerçek
/// donanım gelene kadar cihaz bulunamayacaktır (beklenen davranış).
class AppState extends ChangeNotifier {
  /// İşlem geçmişi bu kadar kayıtla sınırlı (bellek sınırsız büyümesin).
  static const maxLogEntries = 100;

  final SettingsStore settings;
  final SpeechOutput _speech;
  late final FeedbackHub feedback;
  late final CommandRouter router;

  late PatikaBleService bleService;
  bool isSimulated = true;

  BleConnectionState connectionState = BleConnectionState.disconnected;
  List<DiscoveredDevice> devices = [];
  final List<LogEntry> log = [];

  StreamSubscription<BleConnectionState>? _connectionSub;
  StreamSubscription? _commandSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;

  /// Parametreler testlerde sahte uygulamalar vermek için; uygulamada
  /// hepsi gerçek platform uygulamalarına düşer.
  AppState({
    SettingsStore? settings,
    SpeechOutput? speech,
    HapticOutput? haptics,
    EarconPlayer? earcons,
  })  : settings = settings ?? SettingsStore(),
        _speech = speech ?? FlutterTtsOutput() {
    feedback = FeedbackHub(
      queue: AnnouncementQueue(_speech),
      haptics: haptics ?? PhoneHaptics(),
      earcons: earcons ?? AudioplayersEarconPlayer(),
      settings: () => this.settings.value,
    );
    a11y.attachFeedbackHub(feedback);
    router = CommandRouter(settings: SettingsHandler(this.settings));
    this.settings.addListener(_applySettings);
    this.settings.load();
    _applySettings();

    bleService = SimulatedBleService();
    _subscribe();
  }

  void _applySettings() {
    final s = settings.value;
    _speech.configure(rate: s.speechRate, pitch: s.pitch);
    notifyListeners();
  }

  SimulatedBleService get _simulated => bleService as SimulatedBleService;

  void _subscribe() {
    _connectionSub = bleService.connectionState.listen((state) {
      final previous = connectionState;
      connectionState = state;
      // Sadece kalıcı/anlamlı geçişler duyuruluyor - "taranıyor"/"bağlanıyor"
      // gibi ara durumlar sessiz kalıyor. "Koptu" sadece gerçekten bağlıyken
      // söyleniyor (tarama bitince disconnected'a dönmek kopma değil).
      if (state == BleConnectionState.connected &&
          previous != BleConnectionState.connected) {
        feedback.signal(FeedbackEvent.connected,
            text: Tr.glassesConnected, priority: AnnouncementPriority.high);
      } else if (state == BleConnectionState.disconnected &&
          previous == BleConnectionState.connected) {
        feedback.signal(FeedbackEvent.disconnected,
            text: Tr.glassesDisconnected, priority: AnnouncementPriority.high);
      }
      notifyListeners();
    });
    _devicesSub = bleService.discoveredDevices.listen((found) {
      devices = found;
      notifyListeners();
    });
    _commandSub = bleService.commands.listen(_process);
  }

  /// Kaynağı ne olursa olsun (gözlük BLE'si, simülasyon, telefon mikrofonu)
  /// her komutun geçtiği tek yol: route -> log -> sesli sonuç.
  Future<void> _process(BleCommand command) async {
    final result = await router.route(command);
    log.insert(
      0,
      LogEntry(
        time: DateTime.now(),
        intent: command.intent,
        entity: command.entity,
        result: result,
      ),
    );
    if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);
    // Sonuç hem sesle hem titreşimle (+ kısa sesle) bildiriliyor; uzun
    // ayrıntı modunda sonucun açıklaması da okunuyor.
    feedback.result(result);
    notifyListeners();
  }

  Future<void> _unsubscribe() async {
    await _connectionSub?.cancel();
    await _devicesSub?.cancel();
    await _commandSub?.cancel();
  }

  /// Simülasyon <-> gerçek BLE arasında geçiş yapar. Mevcut servis dispose
  /// edilip yenisi kurulur, log geçmişi korunur.
  Future<void> toggleMode(bool simulated) async {
    if (simulated == isSimulated) return;
    await _unsubscribe();
    bleService.dispose();

    isSimulated = simulated;
    bleService = simulated ? SimulatedBleService() : RealBleService();
    devices = [];
    connectionState = BleConnectionState.disconnected;
    _subscribe();
    notifyListeners();
  }

  Future<void> startScan() => bleService.startScan();

  Future<void> connect(String deviceId) => bleService.connect(deviceId);

  Future<void> disconnect() => bleService.disconnect();

  /// Sadece simülasyon modundayken anlamlı - test ekranındaki butonlar bunu
  /// çağırır.
  void injectTestCommand(String intentRaw, {String? entity}) {
    if (!isSimulated) return;
    _simulated.injectCommand(intentRaw, entity: entity);
  }

  /// Telefonun kendi mikrofonundan tanınan komut. BLE servisinden bağımsız
  /// olduğu için hem simülasyon hem gerçek modda çalışır - gözlük donanımı
  /// gerekmez.
  Future<void> submitVoiceCommand(BleCommand command) => _process(command);

  @override
  void dispose() {
    settings.removeListener(_applySettings);
    feedback.queue.stopAll();
    feedback.updateObstacle(null);
    a11y.attachFeedbackHub(null);
    _unsubscribe();
    bleService.dispose();
    super.dispose();
  }
}
