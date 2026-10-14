import 'dart:async';

/// Arayanın nasıl tanındığı (duyuru cümlesi buna göre seçilir).
enum CallerKind {
  /// Rehberde bulundu ya da arama ekranı bir ad gösterdi: [IncomingCall.callerName].
  named,

  /// Arama ekranı bir numara gösterdi ya da ad rehberde yok.
  unknownNumber,

  /// Arayan bilgisi hiç gelmedi (bildirim erişimi kapalı, iOS).
  unidentified,
}

/// Gelen arama bilgisi. Arayanın adı `NotificationListenerService`'ten
/// gelir (bkz. CLAUDE.md, Faz 4b karar 1); numara arama kaydından alınmaz
/// (`READ_CALL_LOG` yok); [number] yalnızca arama ekranı bildirimi numara
/// gösterdiyse (rehberde olmayan arayan) ya da simülasyonda dolu.
class IncomingCall {
  final String callerName;
  final String? number;
  final CallerKind kind;

  const IncomingCall({required this.callerName, this.number, this.kind = CallerKind.named});
}

/// Telefonun arama durumu (Android `TelephonyManager.CALL_STATE_*`; iOS'ta
/// `CXCallObserver` aynı üç durumu verebilir).
enum PhoneCallState {
  idle,

  /// Gelen arama çalıyor.
  ringing,

  /// Bir arama sürüyor (açılmış gelen ya da giden).
  offhook,
}

/// Telefonun gelen arama durumunu bildiren servis. [PatikaBleService]'ten
/// bilerek ayrı: o gözlükle BLE üzerinden konuşur, bu telefonun kendi
/// yeteneğidir (bkz. `DirectActions`, `SentMessageLog` - Faz 4a'da aynı
/// ayrım yapıldı).
///
/// Uygulamalar: Android `MethodChannelCallService` (`CallStateProbe.kt` +
/// arayan adı `PatikaNotificationListener.kt`'ten), Test Modu
/// [SimulatedCallService]. iOS'ta yazılmadı: `CXCallObserver` yalnızca
/// [callState]'i verebilir, arayan adı ve aç/reddet iOS'ta yok
/// ([canAnswer] false olur).
abstract class PatikaCallService {
  /// Arama çalarken dolu; çalmıyorken (bitti/reddedildi/açıldı) null.
  Stream<IncomingCall?> get incomingCall;

  /// Telefonun arama durumu.
  Stream<PhoneCallState> get callState;
  PhoneCallState get currentState;

  /// Aç/reddet bu platformda (ve izinle) yapılabiliyor mu.
  bool get canAnswer;

  /// Arama durumunu izlemeye başlar (izin ÇAĞIRAN tarafta istenir).
  /// İzlenebiliyorsa true.
  Future<bool> start();

  /// Gözlükte dokunma (çalarken): aramayı aç. Açılabildiyse true.
  Future<bool> answer();

  /// Gözlükte uzun basma (çalarken): aramayı reddet. Reddedilebildiyse true.
  Future<bool> reject();

  void dispose();
}
