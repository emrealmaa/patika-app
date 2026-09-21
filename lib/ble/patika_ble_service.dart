import 'ble_command.dart';
import 'ble_connection_state.dart';

/// Gözlükle BLE üzerinden konuşan servisin ortak arayüzü. Gerçek donanım
/// henüz yok - bu arayüz sayesinde [RealBleService] (gerçek flutter_blue_plus)
/// ve [SimulatedBleService] (test modu) `command_router.dart` için birbirinin
/// yerine geçebiliyor; UI ve komut işleme katmanı hangisinin aktif olduğunu
/// hiç bilmez.
abstract class PatikaBleService {
  Stream<BleConnectionState> get connectionState;

  /// Gözlükten ayrıştırılmış (intent, entity) komutları.
  Stream<BleCommand> get commands;

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
