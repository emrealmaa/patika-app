import 'dart:async';

import 'ble_command.dart';
import 'ble_connection_state.dart';
import 'glasses_protocol.dart';

/// Gözlükle BLE üzerinden konuşan servisin ortak arayüzü. Gerçek donanım
/// henüz yok - bu arayüz sayesinde [RealBleService] (flutter_reactive_ble)
/// ve [SimulatedBleService] (test modu) birbirinin yerine geçebiliyor; UI,
/// komut işleme ve bağlantı denetçisi hangisinin aktif olduğunu hiç bilmez.
abstract class PatikaBleService {
  Stream<BleConnectionState> get connectionState;

  /// Gözlükten ayrıştırılmış (intent, entity) komutları.
  Stream<BleCommand> get commands;

  /// Gözlük butonu olayları (Faz 2: dokunuş dinlemeyi başlatır).
  Stream<GlassesButton> get buttonEvents;

  /// Gözlük IMU jestleri.
  Stream<GlassesGesture> get gestureEvents;

  /// Gözlük pil yüzdesi (0-100).
  Stream<int> get batteryLevel;

  /// Gözlüğün "hayattayım" sinyali (bkz. GlassesProtocol.heartbeatInterval).
  Stream<void> get heartbeats;

  /// Taramada bulunan cihazların adı/id'si (bağlanmadan önce listelemek için).
  Stream<List<DiscoveredDevice>> get discoveredDevices;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();

  void dispose();
}

class DiscoveredDevice {
  final String id;
  final String name;

  const DiscoveredDevice({required this.id, required this.name});
}

/// İki servisin ortak gözlük olayı akışları. Servis ham mesajı
/// [GlassesProtocol] ile ayrıştırıp [dispatchGlassesMessage]'a veriyor,
/// doğru akışa dağıtım burada.
mixin GlassesEventStreams {
  final _commandController = StreamController<BleCommand>.broadcast();
  final _buttonController = StreamController<GlassesButton>.broadcast();
  final _gestureController = StreamController<GlassesGesture>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _heartbeatController = StreamController<void>.broadcast();

  Stream<BleCommand> get commands => _commandController.stream;
  Stream<GlassesButton> get buttonEvents => _buttonController.stream;
  Stream<GlassesGesture> get gestureEvents => _gestureController.stream;
  Stream<int> get batteryLevel => _batteryController.stream;
  Stream<void> get heartbeats => _heartbeatController.stream;

  void dispatchGlassesMessage(GlassesMessage message) {
    if (_commandController.isClosed) return;
    switch (message) {
      case CommandMessage(:final command):
        _commandController.add(command);
      case ButtonMessage(:final button):
        _buttonController.add(button);
      case GestureMessage(:final gesture):
        _gestureController.add(gesture);
      case BatteryMessage(:final percent):
        _batteryController.add(percent);
      case HeartbeatMessage():
        _heartbeatController.add(null);
    }
  }

  void closeGlassesStreams() {
    _commandController.close();
    _buttonController.close();
    _gestureController.close();
    _batteryController.close();
    _heartbeatController.close();
  }
}
