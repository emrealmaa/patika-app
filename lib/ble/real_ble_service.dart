import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as fble;
import 'package:permission_handler/permission_handler.dart';

import '../l10n/strings_tr.dart';
import '../permissions/permission_explainer.dart';
import 'ble_connection_state.dart';
import 'glasses_protocol.dart';
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
/// tarafı belirlendiğinde bu sabitler güncellenmeli, geri kalan kod
/// (bağlanma/keşif/subscribe akışı) değişmeden kalabilir.
///
/// Mesaj formatı: bkz. docs/ble_protocol.md ve [GlassesProtocol] - her
/// bildirim/yazma tek bir UTF-8 JSON nesnesi, `"t"` alanı türü belirler.
class RealBleService with GlassesEventStreams implements PatikaBleService {
  static final fble.Uuid _serviceUuid =
      fble.Uuid.parse('0000ff10-0000-1000-8000-00805f9b34fb');
  /// Gözlük -> telefon (notify): komut, buton, jest, pil, heartbeat.
  static final fble.Uuid _eventCharacteristicUuid =
      fble.Uuid.parse('0000ff11-0000-1000-8000-00805f9b34fb');
  /// Telefon -> gözlük (write without response). Şu an gönderilen mesaj yok
  /// (titreşim motoru kalktı); Wi-Fi akışı başlat/durdur taslağı (`frm`,
  /// bkz. docs/ble_protocol.md) için ayrılı.
  // ignore: unused_field
  static final fble.Uuid _controlCharacteristicUuid =
      fble.Uuid.parse('0000ff12-0000-1000-8000-00805f9b34fb');
  /// 247 bayt MTU -> 244 bayt yük; en uzun JSON mesaj buna sığmalı.
  static const _requestedMtu = 247;

  final fble.FlutterReactiveBle _ble = fble.FlutterReactiveBle();
  final PermissionExplainer? _permissions;

  RealBleService({PermissionExplainer? permissions}) : _permissions = permissions;

  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  StreamSubscription<fble.DiscoveredDevice>? _scanSub;
  StreamSubscription<fble.ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _valueSub;
  final List<DiscoveredDevice> _found = [];

  @override
  Stream<BleConnectionState> get connectionState => _connectionController.stream;

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
  ///
  /// İzin penceresinden önce neden gerektiği sesli anlatılıyor
  /// ([PermissionExplainer]) - görme engelli kullanıcı sistem penceresini
  /// bağlamsız duymasın.
  Future<bool> _ensurePermissions() async {
    const permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final explainer = _permissions;
    if (explainer != null) {
      return explainer.ensureAll(permissions, Tr.bluetoothPermissionWhy);
    }
    final statuses = await permissions.request();
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
            _onConnected(deviceId);
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

  Future<void> _onConnected(String deviceId) async {
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: _requestedMtu);
    } catch (e) {
      // MTU pazarlığı başarısız olsa da bağlantı sürer; mesajlar kısa.
      debugPrint('[BLE] MTU istenemedi: $e');
    }
    _subscribeToEventCharacteristic(deviceId);
  }

  fble.QualifiedCharacteristic _characteristic(String deviceId, fble.Uuid id) =>
      fble.QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: _serviceUuid,
        characteristicId: id,
      );

  void _subscribeToEventCharacteristic(String deviceId) {
    final characteristic = _characteristic(deviceId, _eventCharacteristicUuid);

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
    // Bozuk/eksik/tanınmayan bir paket akışı asla kilitlememeli - decode
    // null döner ve sessizce atlanır ("asla çökmesin" ilkesi).
    final message = GlassesProtocol.decode(value);
    if (message != null) dispatchGlassesMessage(message);
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
    _devicesController.close();
    closeGlassesStreams();
  }
}
