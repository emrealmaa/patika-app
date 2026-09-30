import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Açık mod için kullanıcının BU CİHAZDA verdiği onay (Faz 7c-2). Gerçek
/// depo `FallOpenConsentStorage.kt` (`noBackupFilesDir`): yedekten ve cihaz
/// aktarımından gelmez. Ayarlarda `on` yedekten gelse bile onay dosyası yeni
/// cihazda yoktur; açık mod silahlanmaz, iki adımlı onay yeniden istenir.
///
/// Belirsizlik her zaman güvenli yöne çözülür: okunamazsa "onay yok", yazılamazsa
/// "kaydedilemedi" (açılmaz).
abstract class FallConsentStore {
  /// Bu cihazda açık mod onayı verilmiş mi?
  Future<bool> granted();

  /// Onayı kaydeder; kaydedilemediyse false (açık mod açılmaz).
  Future<bool> grant();

  /// Onayı siler (açık mod kapanınca ya da kapı bozulunca).
  Future<void> revoke();
}

/// Gerçek depo: kanal `patika/fall_consent`.
class MethodChannelFallConsentStore implements FallConsentStore {
  static const _channel = MethodChannel('patika/fall_consent');

  @override
  Future<bool> granted() async {
    try {
      return await _channel.invokeMethod<bool>('granted') ?? false;
    } catch (e) {
      debugPrint('[Düşme] onay okunamadı: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> grant() async {
    try {
      return await _channel.invokeMethod<bool>('grant') ?? false;
    } catch (e) {
      debugPrint('[Düşme] onay yazılamadı: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<void> revoke() async {
    try {
      await _channel.invokeMethod<void>('revoke');
    } catch (e) {
      debugPrint('[Düşme] onay silinemedi: ${e.runtimeType}');
    }
  }
}

/// Bellekte depo (testler ve kanalı olmayan ortam).
class MemoryFallConsentStore implements FallConsentStore {
  bool value;

  /// true iken [grant] başarısız olur (depo hatası testi).
  bool failGrant = false;

  MemoryFallConsentStore({this.value = false});

  @override
  Future<bool> granted() async => value;

  @override
  Future<bool> grant() async {
    if (failGrant) return false;
    value = true;
    return true;
  }

  @override
  Future<void> revoke() async => value = false;
}
