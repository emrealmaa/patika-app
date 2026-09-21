import 'dart:async';

import 'package:flutter/foundation.dart';

import 'accessibility/a11y_announcer.dart' as a11y;
import 'ble/ble_connection_state.dart';
import 'ble/patika_ble_service.dart';
import 'ble/real_ble_service.dart';
import 'ble/simulated_ble_service.dart';
import 'commands/command_router.dart';
import 'commands/log_entry.dart';

/// Uygulamanın tek merkezi durumu. BLE servisi (gerçek/simüle) ile komut
/// yönlendiriciyi (CommandRouter) birbirine bağlar, ekranlar (ConnectionScreen/
/// TestModeScreen) sadece bunu dinler - hangi BLE implementasyonunun aktif
/// olduğunu bilmeleri gerekmez.
///
/// Donanım henüz olmadığı için varsayılan mod SİMÜLASYON - gerçek moda
/// geçmek (RealBleService) ekrandaki bir switch ile mümkün, ama gerçek
/// donanım gelene kadar cihaz bulunamayacaktır (beklenen davranış).
class AppState extends ChangeNotifier {
  final CommandRouter router = CommandRouter();

  late PatikaBleService bleService;
  bool isSimulated = true;

  BleConnectionState connectionState = BleConnectionState.disconnected;
  List<DiscoveredDevice> devices = [];
  final List<LogEntry> log = [];

  StreamSubscription<BleConnectionState>? _connectionSub;
  StreamSubscription? _commandSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;

  AppState() {
    bleService = SimulatedBleService();
    _subscribe();
  }

  SimulatedBleService get _simulated => bleService as SimulatedBleService;

  void _subscribe() {
    _connectionSub = bleService.connectionState.listen((state) {
      final previous = connectionState;
      connectionState = state;
      // Sadece kalıcı/anlamlı geçişler duyuruluyor - "taranıyor"/"bağlanıyor"
      // gibi ara durumlar sessiz kalıyor (bkz. a11y_announcer.dart).
      if (state != previous) {
        if (state == BleConnectionState.connected) {
          a11y.announce('Gözlük bağlandı');
        } else if (state == BleConnectionState.disconnected) {
          a11y.announce('Gözlük bağlantısı koptu');
        }
      }
      notifyListeners();
    });
    _devicesSub = bleService.discoveredDevices.listen((found) {
      devices = found;
      notifyListeners();
    });
    _commandSub = bleService.commands.listen((command) async {
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
      // result.message zaten "kullanıcıya seslendirilecek yanıt metni"
      // olarak tasarlandı (bkz. action_result.dart) - hem komutun
      // algılandığını hem sonucunu (başarılı/başarısız) tek, doğal bir
      // cümlede taşıyor.
      a11y.announce(result.message);
      notifyListeners();
    });
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

  @override
  void dispose() {
    _unsubscribe();
    bleService.dispose();
    super.dispose();
  }
}
