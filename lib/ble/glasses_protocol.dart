import 'dart:convert';

import '../accessibility/haptic_patterns.dart';
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

  /// Gözlükte titreşim deseni çaldırır. [scale] 0..1 kullanıcı şiddeti,
  /// yüzdeye çevrilerek gönderilir.
  static List<int> encodeHaptic(HapticPatternId id, double scale) => _encode({
        't': 'hap',
        'id': id.wireId,
        's': (scale.clamp(0.0, 1.0) * 100).round(),
      });

  static List<int> _encode(Map<String, Object> message) =>
      utf8.encode(jsonEncode(message));

  static T? _byWire<T>(List<T> values, Object? wire, String Function(T) wireOf) {
    for (final v in values) {
      if (wireOf(v) == wire) return v;
    }
    return null;
  }
}
