import 'dart:convert';

import 'ble_command.dart';

/// Gözlük butonu olayları.
enum GlassesButton {
  tap('tap'),
  doubleTap('double'),
  longPress('long');

  final String wire;
  const GlassesButton(this.wire);
}

/// Gözlük IMU jestleri.
enum GlassesGesture {
  doubleNod('nod2');

  final String wire;
  const GlassesGesture(this.wire);
}

/// Gözlükten gelen, ayrıştırılmış tek bir mesaj.
sealed class GlassesMessage {
  const GlassesMessage();
}

class CommandMessage extends GlassesMessage {
  final BleCommand command;
  const CommandMessage(this.command);
}

class ButtonMessage extends GlassesMessage {
  final GlassesButton button;
  const ButtonMessage(this.button);
}

class GestureMessage extends GlassesMessage {
  final GlassesGesture gesture;
  const GestureMessage(this.gesture);
}

class BatteryMessage extends GlassesMessage {
  final int percent;
  const BatteryMessage(this.percent);
}

class HeartbeatMessage extends GlassesMessage {
  final int? seq;
  const HeartbeatMessage([this.seq]);
}

/// Gözlüğün Wi-Fi SoftAP bilgisi (kamera akışı için, bkz. ble_protocol.md §7).
/// **TASLAK, firmware'de doğrulanacak.** Parola günlüğe/geçmişe yazılmaz.
class GlassesWifiCredentials {
  final String ssid;

  /// Açık (parolasız) SoftAP'ta null.
  final String? passphrase;

  const GlassesWifiCredentials(this.ssid, [this.passphrase]);

  @override
  bool operator ==(Object other) =>
      other is GlassesWifiCredentials && other.ssid == ssid && other.passphrase == passphrase;

  @override
  int get hashCode => Object.hash(ssid, passphrase);

  /// Parola bilerek gösterilmez.
  @override
  String toString() => 'GlassesWifiCredentials($ssid)';
}

class WifiCredentialsMessage extends GlassesMessage {
  final GlassesWifiCredentials credentials;
  const WifiCredentialsMessage(this.credentials);
}

/// Gözlük <-> telefon BLE mesaj formatı (bkz. docs/ble_protocol.md).
///
/// Her BLE bildirimi/yazması tek bir UTF-8 JSON nesnesi; `"t"` alanı mesaj
/// türünü belirler. Tanınmayan/bozuk mesajlar null döner ve sessizce
/// atlanır - firmware'e yeni bir tür eklenmesi uygulamayı asla çökertmez.
abstract final class GlassesProtocol {
  /// Gözlük bu aralıkla heartbeat gönderir.
  static const heartbeatInterval = Duration(seconds: 2);

  /// Bu süre heartbeat gelmezse bağlantı kopmuş sayılır (3 aralık).
  static const heartbeatTimeout = Duration(seconds: 6);

  /// MTU pazarlığı başarısız olursa (23) bir yazmanın yükü. Telefonun
  /// gözlüğe yazdığı her mesaj buna sığar (ble_protocol.md §2).
  static const minPayload = 20;

  /// Telefon -> gözlük: kamera akışını (SoftAP + MJPEG) başlat/durdur.
  /// `on` 1/0 (bool değil): `{"t":"frm","on":0}` 18 bayt, `false` ile 22
  /// bayt olur ve [minPayload]'a sığmazdı.
  /// **TASLAK, firmware'de netleşecek** (ble_protocol.md §2.2, §7).
  static List<int> encodeFrm(bool on) => utf8.encode(jsonEncode({'t': 'frm', 'on': on ? 1 : 0}));

  /// Telefon -> gözlük yazmasını çözer (simülasyon ve testler için); `frm`
  /// değilse ya da bozuksa null.
  static bool? decodeFrm(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['t'] != 'frm') return null;
      return switch (json['on']) { 1 => true, 0 => false, _ => null };
    } catch (_) {
      return null;
    }
  }

  static GlassesMessage? decode(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) return null;
      return decodeJson(json);
    } catch (_) {
      return null;
    }
  }

  static GlassesMessage? decodeJson(Map<String, dynamic> json) {
    switch (json['t']) {
      case 'cmd':
        return _command(json);
      case 'btn':
        final button = _byWire(GlassesButton.values, json['a'], (b) => b.wire);
        return button == null ? null : ButtonMessage(button);
      case 'gst':
        final gesture = _byWire(GlassesGesture.values, json['g'], (g) => g.wire);
        return gesture == null ? null : GestureMessage(gesture);
      case 'batt':
        final v = json['v'];
        return v is int ? BatteryMessage(v.clamp(0, 100)) : null;
      case 'hb':
        final seq = json['seq'];
        return HeartbeatMessage(seq is int ? seq : null);
      case 'wifi':
        return _wifi(json);
      case null:
        // İlk taslaktaki "t"siz format ({"intent": ..., "entity": ...})
        // geriye dönük uyumluluk için hâlâ komut sayılıyor.
        return json.containsKey('intent') ? _command(json) : null;
      default:
        return null;
    }
  }

  static CommandMessage _command(Map<String, dynamic> json) {
    final intent = json['intent'];
    final entity = json['entity'];
    return CommandMessage(BleCommand.fromWire(
      intent is String ? intent : 'BİLİNMİYOR',
      entity is String ? entity : null,
    ));
  }

  /// `{"t":"wifi","ssid":"Patika-1A2B","pass":"..."}` (taslak). SSID 1-32
  /// bayt; parola varsa WPA2 kuralı 8-63 karakter. Kurala uymayan mesaj
  /// atlanır (sistem ağ isteği zaten reddederdi).
  static WifiCredentialsMessage? _wifi(Map<String, dynamic> json) {
    final ssid = json['ssid'];
    final pass = json['pass'];
    if (ssid is! String || ssid.isEmpty || utf8.encode(ssid).length > 32) return null;
    if (pass != null && (pass is! String || pass.length < 8 || pass.length > 63)) return null;
    return WifiCredentialsMessage(GlassesWifiCredentials(ssid, pass as String?));
  }

  static T? _byWire<T>(List<T> values, Object? wire, String Function(T) wireOf) {
    for (final v in values) {
      if (wireOf(v) == wire) return v;
    }
    return null;
  }
}
