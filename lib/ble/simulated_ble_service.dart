import 'dart:async';

import 'ble_command.dart';
import 'ble_connection_state.dart';
import 'glasses_protocol.dart';
import 'patika_ble_service.dart';

/// Gözlük donanımı henüz yokken BLE bağlantısını ve gözlükten gelen
/// olayları simüle eden servis. Gerçek [RealBleService] ile aynı arayüzü
/// ([PatikaBleService]) uyguladığı için test modundan sahte komut/buton/
/// jest/pil olayları ve bağlantı sorunları (donma, menzil dışı) enjekte
/// edilip üstteki zincirin tamamı (bağlantı denetçisi, komut işleme,
/// duyurular) gerçek donanım olmadan test edilebilir.
class SimulatedBleService with GlassesEventStreams implements PatikaBleService {
  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  BleConnectionState _state = BleConnectionState.disconnected;
  Timer? _heartbeatTimer;
  int _heartbeatSeq = 0;
  bool _heartbeatPaused = false;
  bool _reachable = true;
  int _battery = 80;

  static const _fakeDevice = DiscoveredDevice(
    id: 'SIM-ESP32-S3-0001',
    name: 'Patika Gözlük (simülasyon)',
  );

  @override
  Stream<BleConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;

  bool get heartbeatPaused => _heartbeatPaused;
  bool get reachable => _reachable;
  int get battery => _battery;

  @override
  Future<void> startScan() async {
    _setState(BleConnectionState.scanning);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!_devicesController.isClosed) {
      _devicesController.add(_reachable ? const [_fakeDevice] : const []);
    }
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> stopScan() async {
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    _setState(BleConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 500));
    if (_state != BleConnectionState.connecting) return;
    if (!_reachable) {
      // Gerçek BLE'deki bağlantı zaman aşımının karşılığı.
      _setState(BleConnectionState.disconnected);
      return;
    }
    _setState(BleConnectionState.connected);
    _startHeartbeat();
    dispatchGlassesMessage(BatteryMessage(_battery));
  }

  @override
  Future<void> disconnect() async {
    _stopHeartbeat();
    _setState(BleConnectionState.disconnected);
  }

  /// Test ekranındaki komut girişi bunu çağırır. Bağlı değilken de çalışır
  /// (bağlantı olmadan komut akışını test edebilmek için kasıtlı).
  void injectCommand(String intentRaw, {String? entity}) =>
      dispatchGlassesMessage(CommandMessage(BleCommand.fromWire(intentRaw, entity)));

  void injectButton(GlassesButton button) =>
      dispatchGlassesMessage(ButtonMessage(button));

  void injectGesture(GlassesGesture gesture) =>
      dispatchGlassesMessage(GestureMessage(gesture));

  void setBattery(int percent) {
    _battery = percent.clamp(0, 100);
    if (_state == BleConnectionState.connected) {
      dispatchGlassesMessage(BatteryMessage(_battery));
    }
  }

  /// Gözlüğün donmasını taklit eder: bağlantı BLE seviyesinde açık görünür
  /// ama heartbeat gelmez - bağlantı denetçisi bunu yakalamalı.
  void setHeartbeatPaused(bool paused) => _heartbeatPaused = paused;

  /// Menzil dışını taklit eder: bağlıysa bağlantı kopar ve erişilebilir
  /// olana kadar her bağlanma denemesi başarısız olur.
  void setReachable(bool reachable) {
    _reachable = reachable;
    if (!reachable && _state == BleConnectionState.connected) {
      _stopHeartbeat();
      _setState(BleConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(GlassesProtocol.heartbeatInterval, (_) {
      if (!_heartbeatPaused) dispatchGlassesMessage(HeartbeatMessage(_heartbeatSeq++));
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _setState(BleConnectionState state) {
    _state = state;
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _connectionController.close();
    _devicesController.close();
    closeGlassesStreams();
  }
}
