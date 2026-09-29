import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Telefonun pil okuması: yüzde (0-100) ve şarjda olup olmadığı.
class PhoneBatteryReading {
  final int percent;
  final bool charging;

  const PhoneBatteryReading(this.percent, {this.charging = false});
}

/// Telefon pilini okuyan kaynak. Okunamazsa `null` ("bilinmiyor"): uydurma
/// değer söylenmez.
abstract class PhoneBattery {
  Future<PhoneBatteryReading?> read();
}

/// Gerçek okuma: `BatteryProbe.kt` (kanal `patika/battery`). İzin gerektirmez.
class MethodChannelPhoneBattery implements PhoneBattery {
  static const _channel = MethodChannel('patika/battery');

  @override
  Future<PhoneBatteryReading?> read() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('read');
      final level = map?['level'];
      if (level is! int) return null;
      return PhoneBatteryReading(level.clamp(0, 100), charging: map?['charging'] == true);
    } catch (e) {
      debugPrint('[Pil] telefon pili okunamadı: ${e.runtimeType}');
      return null;
    }
  }
}

/// Test Modu için: [force] verilirse gerçek okumanın yerine o döner, verilmezse
/// ([clear]) gerçek kaynağa düşer. Gerçek telefonda düşük pil uyarısını denemek
/// için pili gerçekten boşaltmak gerekmesin.
class OverridablePhoneBattery implements PhoneBattery {
  final PhoneBattery _inner;
  PhoneBatteryReading? _override;

  OverridablePhoneBattery(this._inner);

  PhoneBatteryReading? get current => _override;

  void force(PhoneBatteryReading reading) => _override = reading;

  void clear() => _override = null;

  @override
  Future<PhoneBatteryReading?> read() async => _override ?? await _inner.read();
}
