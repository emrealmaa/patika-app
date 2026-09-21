import 'dart:async';

import 'ble_command.dart';
import 'ble_connection_state.dart';
import 'patika_ble_service.dart';

/// Gözlük donanımı henüz yokken BLE bağlantısını ve gözlükten gelen
/// komutları simüle eden servis. Gerçek [RealBleService] ile aynı arayüzü
/// ([PatikaBleService]) uyguladığı için `test_mode_screen.dart` üzerinden
/// sahte komutlar enjekte edilip komut işleme zincirinin (parse -> route ->
/// handler) tamamı gerçek donanım olmadan test edilebilir.
class SimulatedBleService implements PatikaBleService {
  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final _commandController = StreamController<BleCommand>.broadcast();
  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  BleConnectionState _state = BleConnectionState.disconnected;

  static const _fakeDevice = DiscoveredDevice(
    id: 'SIM-ESP32-S3-0001',
    name: 'Patika Gözlük (simülasyon)',
  );

  @override
  Stream<BleConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<BleCommand> get commands => _commandController.stream;

  @override
  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;

  @override
  Future<void> startScan() async {
    _setState(BleConnectionState.scanning);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!_devicesController.isClosed) {
      _devicesController.add([_fakeDevice]);
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
    _setState(BleConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _setState(BleConnectionState.disconnected);
  }

  /// Test ekranındaki butonlar/metin girişi bu metodu çağırıp gözlükten
  /// geliyormuş gibi bir komut enjekte eder. Bağlı değilken de çalışır
  /// (bağlantı olmadan komut akışını test edebilmek için kasıtlı).
  void injectCommand(String intentRaw, {String? entity}) {
    _commandController.add(BleCommand.fromWire(intentRaw, entity));
  }

  void _setState(BleConnectionState state) {
    _state = state;
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
  }

  @override
  void dispose() {
    _connectionController.close();
    _commandController.close();
    _devicesController.close();
  }
}
