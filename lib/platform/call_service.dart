import 'dart:async';

/// Gelen arama bilgisi. Arayanın adı `NotificationListenerService`'ten
/// gelecek (bkz. CLAUDE.md, Faz 4b); numara varsa aç/reddet için saklanır.
class IncomingCall {
  final String callerName;
  final String? number;

  const IncomingCall({required this.callerName, this.number});
}

/// Telefonun gelen arama durumunu bildiren servis. [PatikaBleService]'ten
/// bilerek ayrı: o gözlükle BLE üzerinden konuşur, bu telefonun kendi
/// yeteneğidir (bkz. `DirectActions`, `SentMessageLog` - Faz 4a'da aynı
/// ayrım yapıldı). Gerçek uygulama `PatikaNotificationListener.kt` +
/// `NotificationListenerService` olacak (Faz 4b'nin son adımı); şimdilik
/// yalnızca arayüz ve [SimulatedCallService] var.
abstract class PatikaCallService {
  /// Arama çalarken dolu; çalmıyorken (bitti/reddedildi/açıldı) null.
  Stream<IncomingCall?> get incomingCall;

  /// Gözlükte dokunma (çalarken): aramayı aç.
  Future<void> answer();

  /// Gözlükte uzun basma (çalarken): aramayı reddet.
  Future<void> reject();

  void dispose();
}
