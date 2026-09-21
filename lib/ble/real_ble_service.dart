import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as fble;
import 'package:permission_handler/permission_handler.dart';

import 'ble_command.dart';
import 'ble_connection_state.dart';
import 'patika_ble_service.dart';

/// Gerçek ESP32-S3 gözlükle BLE üzerinden konuşan servis.
///
/// `flutter_reactive_ble` kullanıyor (BSD-3-Clause - ücretsiz, ticari
/// kullanımda hiçbir kısıtlama/ücret yok). Önceki taslak `flutter_blue_plus`
/// ile yazılmıştı ama o paketin 2.x sürümü for-profit kullanımda (şirket
/// büyüklüğünden bağımsız - geliştirme/test dahil) ücretli lisans şartı
/// getiriyordu, bu yüzden değiştirildi (bkz. patika_app/TODO.md).
///
/// ÖNEMLİ: Aşağıdaki UUID'ler PLACEHOLDER'dır - henüz donanım/firmware
/// olmadığı için gerçek servis/karakteristik UUID'leri bilinmiyor. Firmware
/// tarafı belirlendiğinde bu üç sabit güncellenmeli, geri kalan kod
/// (bağlanma/keşif/subscribe akışı) değişmeden kalabilir.
///
/// Beklenen mesaj formatı (karakteristik üzerinden UTF-8 JSON, tek satır):
/// {"intent": "ARA", "entity": "Emre"}
/// Bu, Python tarafındaki intent_classifier.siniflandir()'in (intent, entity,
/// cevap) çıktısıyla aynı sözlüğü paylaşacak şekilde tasarlandı - "cevap"
/// alanı henüz kullanılmıyor (bkz. NOTES.md).
class RealBleService implements PatikaBleService {
  static final fble.Uuid _serviceUuid =
      fble.Uuid.parse('0000ff10-0000-1000-8000-00805f9b34fb');
  static final fble.Uuid _commandCharacteristicUuid =
      fble.Uuid.parse('0000ff11-0000-1000-8000-00805f9b34fb');

  final fble.FlutterReactiveBle _ble = fble.FlutterReactiveBle();

  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final _commandController = StreamController<BleCommand>.broadcast();
  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  StreamSubscription<fble.DiscoveredDevice>? _scanSub;
  StreamSubscription<fble.ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _valueSub;
  final List<DiscoveredDevice> _found = [];

  @override
  Stream<BleConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<BleCommand> get commands => _commandController.stream;

  @override
  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;

  /// Android 12+ (API 31+), BLUETOOTH_SCAN/BLUETOOTH_CONNECT'i manifest'te
  /// tanımlamak yetmiyor - "tehlikeli" izinler gibi çalışma zamanında da
  /// kullanıcıdan onay istenmesi gerekiyor (izin verilmezse tarama/bağlanma
  /// sessizce başarısız olur ya da platform istisnası fırlatır). API 30 ve
  /// altında BLE taraması için konum izni gerekiyordu, o da isteniyor.
  /// iOS'ta bu izinler `permission_handler` tarafında no-op/otomatik granted
  /// döner - gerçek CoreBluetooth izni Info.plist'teki açıklamayla ilk
  /// kullanımda sistem tarafından sorulur.
  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  @override
  Future<void> startScan() async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _connectionController.add(BleConnectionState.disconnected);
      return;
    }

    _connectionController.add(BleConnectionState.scanning);
    _found.clear();
    await _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(withServices: [_serviceUuid], scanMode: fble.ScanMode.balanced)
        .listen(
      (device) {
        if (device.name.isEmpty) return;
        if (_found.any((d) => d.id == device.id)) return;
        _found.add(DiscoveredDevice(id: device.id, name: device.name));
        _devicesController.add(List.unmodifiable(_found));
      },
      onError: (_) {
        // Tarama hatası (BLE kapalı, izin yok vb.) sessizce yutuluyor -
        // kullanıcı "hiç cihaz bulunamadı" durumunu ekranda zaten görüyor,
        // ayrı bir hata akışı v1 kapsamında yok.
      },
    );
  }

  @override
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (_connectionSub == null) {
      _connectionController.add(BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _connectionController.add(BleConnectionState.disconnected);
      return;
    }

    await _scanSub?.cancel();
    _connectionController.add(BleConnectionState.connecting);

    await _connectionSub?.cancel();
    // reactive_ble'de bağlantı, dönen stream'i DİNLEMEKLE kurulur ve stream
    // subscription'ı İPTAL ETMEKLE kesilir - flutter_blue_plus'taki ayrı
    // connect()/disconnect() metodlarının aksine, "bağlı kalma" durumu bu
    // subscription'ın canlılığına bağlı (bkz. paket dokümantasyonu).
    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
        .listen(
      (update) {
        switch (update.connectionState) {
          case fble.DeviceConnectionState.connected:
            _connectionController.add(BleConnectionState.connected);
            _subscribeToCommandCharacteristic(deviceId);
            break;
          case fble.DeviceConnectionState.disconnected:
            _connectionController.add(BleConnectionState.disconnected);
            break;
          case fble.DeviceConnectionState.connecting:
            _connectionController.add(BleConnectionState.connecting);
            break;
          case fble.DeviceConnectionState.disconnecting:
            break;
        }
      },
      onError: (_) {
        _connectionController.add(BleConnectionState.disconnected);
      },
    );
  }

  void _subscribeToCommandCharacteristic(String deviceId) {
    final characteristic = fble.QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _serviceUuid,
      characteristicId: _commandCharacteristicUuid,
    );

    _valueSub?.cancel();
    _valueSub = _ble.subscribeToCharacteristic(characteristic).listen(
      _onRawValue,
      onError: (_) {
        // Karakteristik henüz keşfedilmemiş/desteklenmiyor olabilir (gerçek
        // firmware olmadan doğrulanamadı) - bağlantıyı düşürmüyor, sadece
        // komut akışı boş kalıyor.
      },
    );
  }

  void _onRawValue(List<int> value) {
    if (value.isEmpty) return;
    try {
      final text = utf8.decode(value);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final intentRaw = json['intent'] as String? ?? 'BİLİNMİYOR';
      final entity = json['entity'] as String?;
      _commandController.add(BleCommand.fromWire(intentRaw, entity));
    } catch (_) {
      // Bozuk/eksik bir paket komut akışını asla kilitlememeli - sessizce
      // atlanıyor (main.py'deki "asla çökmesin" ilkesiyle aynı ruh).
    }
  }

  @override
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    // Bağlantıyı kesmenin yolu bu: connectToDevice()'ın stream'ini iptal
    // etmek (bkz. yukarıdaki not) - ayrı bir disconnect() API'si yok.
    await _connectionSub?.cancel();
    _connectionSub = null;
    _connectionController.add(BleConnectionState.disconnected);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _valueSub?.cancel();
    _connectionController.close();
    _commandController.close();
    _devicesController.close();
  }
}
