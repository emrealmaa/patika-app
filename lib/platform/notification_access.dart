import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bildirim dinleyici erişimi (`NotificationListenerService`) - normal
/// çalışma zamanı izinlerinden farklı: `permission_handler`'ın
/// request/response akışına girmez. Kullanıcı sistem ayarlarından elle
/// açıp kapatır; uygulama yalnızca durumu sorabilir ve o ekranı açabilir.
/// Gerçek dinleyici (`PatikaNotificationListener.kt`) henüz yazılmadı -
/// bu yalnızca izin/kanal iskeleti (Faz 4b).
abstract class NotificationAccess {
  /// Uygulama şu an etkin bir bildirim dinleyicisi mi.
  Future<bool> isEnabled();

  /// Sistemin "Bildirim erişimi" ayar ekranını açar; kullanıcı listede
  /// Patika'yı bulup elle açar/kapatır.
  Future<void> openSettings();
}

class MethodChannelNotificationAccess implements NotificationAccess {
  static const _channel = MethodChannel('patika/notifications');

  @override
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (e) {
      // Android dışı platform ya da testler.
      debugPrint('[Notifications] durum sorgulanamadı: $e');
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (e) {
      debugPrint('[Notifications] ayarlar açılamadı: $e');
    }
  }
}

/// Testlerde ve Android dışı platformlarda varsayılan.
class NoNotificationAccess implements NotificationAccess {
  const NoNotificationAccess();

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> openSettings() async {}
}
