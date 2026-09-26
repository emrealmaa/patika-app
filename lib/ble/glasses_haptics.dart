import '../accessibility/haptic_patterns.dart';
import 'patika_ble_service.dart';

/// Titreşim desenini gözlüğe BLE ile (desen ID'si olarak) gönderir.
///
/// Engel titreşimi ([updateObstacle]) BİLEREK gönderilmiyor: engel algılama
/// -> titreşim döngüsü gözlüğün içinde, telefondan bağımsız çalışmalı (BLE
/// koparsa ya da telefon kapanırsa da kullanıcı uyarı almalı - bkz.
/// docs/ble_protocol.md). Telefon tarafındaki engel titreşimi sadece
/// simülasyon/test içindir.
class GlassesHaptics implements HapticOutput {
  /// Servis simülasyon/gerçek arasında değişebildiği için her seferinde
  /// güncelini alıyor.
  final PatikaBleService Function() _service;

  GlassesHaptics(this._service);

  @override
  Future<void> play(HapticPatternId id, {required double scale}) async {
    if (scale <= 0) return;
    await _service().sendHapticPattern(id, scale: scale);
  }

  @override
  void updateObstacle(double? distanceMeters, {required double scale}) {}
}
