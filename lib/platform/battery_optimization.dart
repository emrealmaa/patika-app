import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Pil optimizasyonu muafiyeti isteğinin nasıl açıldığı.
enum BatteryExemptionUi {
  /// `direct`: sistem penceresi (izinle).
  dialog,

  /// `play` (ya da pencere açılamadı): liste ayar ekranı, kullanıcı elle seçer.
  settings,

  /// Hiçbiri açılamadı.
  failed,
}

/// Pil optimizasyonu (Doze) muafiyeti: ekran kapalıyken saatlerce çalışma.
/// Bkz. `BatteryOptimization.kt`.
abstract class BatteryOptimization {
  /// Uygulama zaten muaf mı.
  Future<bool> isIgnoring();

  /// Pencereyi (direct) ya da ayar ekranını (play) açar. Sonuç geri dönmez:
  /// [isIgnoring] ile yoklanır.
  Future<BatteryExemptionUi> request();
}

class MethodChannelBatteryOptimization implements BatteryOptimization {
  static const _channel = MethodChannel('patika/battery_optimization');

  const MethodChannelBatteryOptimization();

  @override
  Future<bool> isIgnoring() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoring') ?? false;
    } on MissingPluginException {
      // iOS / testler: bu kavram yok, istenecek bir şey de yok.
      return true;
    } catch (e) {
      debugPrint('[BatteryOpt] sorgulanamadı: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<BatteryExemptionUi> request() async {
    try {
      return switch (await _channel.invokeMethod<String>('request')) {
        'dialog' => BatteryExemptionUi.dialog,
        'settings' => BatteryExemptionUi.settings,
        _ => BatteryExemptionUi.failed,
      };
    } catch (e) {
      debugPrint('[BatteryOpt] açılamadı: ${e.runtimeType}');
      return BatteryExemptionUi.failed;
    }
  }
}

/// Testlerde ve muafiyet kavramı olmayan platformlarda: zaten muaf sayılır,
/// hiçbir şey sorulmaz.
class NoBatteryOptimization implements BatteryOptimization {
  const NoBatteryOptimization();

  @override
  Future<bool> isIgnoring() async => true;

  @override
  Future<BatteryExemptionUi> request() async => BatteryExemptionUi.failed;
}
