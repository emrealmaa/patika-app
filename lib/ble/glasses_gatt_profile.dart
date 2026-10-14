/// Gözlüğün BLE GATT profili: servis ve karakteristik UUID'lerinin TEK
/// kaynağı. Başka hiçbir dosyada UUID sabiti yok (testle kilitli,
/// `test/gatt_profile_test.dart`).
///
/// ⚠️ **Varsayılan değerler PLACEHOLDER'dır** - ESP32-S3 firmware'i henüz yok,
/// gerçek UUID'ler bilinmiyor (bkz. docs/ble_protocol.md "Firmware'de
/// doğrulanacak"). Firmware gelince kod değiştirmeden derleme anında:
///
/// ```
/// --dart-define=PATIKA_BLE_SERVICE_UUID=...
/// --dart-define=PATIKA_BLE_EVENT_UUID=...
/// --dart-define=PATIKA_BLE_CONTROL_UUID=...
/// ```
///
/// Biçimi bozuk bir değer verilirse sessizce placeholder'a düşülmez:
/// [GlassesGattProfile.fromDefines] hatayı [invalid] listesinde döndürür ve
/// o alan için placeholder kullanılır (uygulama açılır; tarama gerçek gözlüğü
/// bulamaz, bu da günlüğe yazılır).
class GlassesGattProfile {
  /// Patika servisi (reklamda yayınlanır, tarama bununla süzülür).
  final String service;

  /// Gözlük -> telefon (notify): komut, buton, jest, pil, heartbeat, wifi.
  final String eventCharacteristic;

  /// Telefon -> gözlük (write without response): `frm`.
  final String controlCharacteristic;

  /// Geçersiz biçimde verilip yok sayılan dart-define adları.
  final List<String> invalid;

  const GlassesGattProfile({
    required this.service,
    required this.eventCharacteristic,
    required this.controlCharacteristic,
    this.invalid = const [],
  });

  /// PLACEHOLDER değerler (Bluetooth taban UUID'sinde 0xFF10..0xFF12).
  static const placeholder = GlassesGattProfile(
    service: '0000ff10-0000-1000-8000-00805f9b34fb',
    eventCharacteristic: '0000ff11-0000-1000-8000-00805f9b34fb',
    controlCharacteristic: '0000ff12-0000-1000-8000-00805f9b34fb',
  );

  /// Değerler hâlâ placeholder mı (firmware UUID'leri girilmedi).
  bool get isPlaceholder =>
      service == placeholder.service &&
      eventCharacteristic == placeholder.eventCharacteristic &&
      controlCharacteristic == placeholder.controlCharacteristic;

  static const _serviceDefine = String.fromEnvironment('PATIKA_BLE_SERVICE_UUID');
  static const _eventDefine = String.fromEnvironment('PATIKA_BLE_EVENT_UUID');
  static const _controlDefine = String.fromEnvironment('PATIKA_BLE_CONTROL_UUID');

  /// Derleme anındaki dart-define değerleri (yoksa placeholder).
  factory GlassesGattProfile.fromDefines() =>
      resolve(service: _serviceDefine, event: _eventDefine, control: _controlDefine);

  /// [fromDefines]'ın saf mantığı (testlerde değer verilir). Boş = verilmedi.
  static GlassesGattProfile resolve({String service = '', String event = '', String control = ''}) {
    final invalid = <String>[];
    String pick(String value, String fallback, String name) {
      if (value.isEmpty) return fallback;
      final normalized = value.trim().toLowerCase();
      if (!isValidUuid(normalized)) {
        invalid.add(name);
        return fallback;
      }
      return normalized;
    }

    return GlassesGattProfile(
      service: pick(service, placeholder.service, 'PATIKA_BLE_SERVICE_UUID'),
      eventCharacteristic: pick(event, placeholder.eventCharacteristic, 'PATIKA_BLE_EVENT_UUID'),
      controlCharacteristic:
          pick(control, placeholder.controlCharacteristic, 'PATIKA_BLE_CONTROL_UUID'),
      invalid: invalid,
    );
  }

  /// 128 bit UUID, `8-4-4-4-12` onaltılık.
  static bool isValidUuid(String s) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(s);
}
