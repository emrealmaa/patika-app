import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../accessibility/feedback_hub.dart';
import '../l10n/strings_tr.dart';
import '../platform/notification_access.dart';

/// Çalışma zamanı izinlerini "önce sesli açıkla, sonra sor" şeklinde ister.
/// Görme engelli kullanıcı sistem izin penceresini bağlamsız duymasın:
/// neden gerektiği önce TTS ile anlatılıyor, konuşma bitince pencere
/// açılıyor. Reddedilirse bu da sesle bildiriliyor.
class PermissionExplainer {
  final FeedbackHub _feedback;

  /// TTS takılırsa (motor yok vb.) izin penceresi sonsuza dek beklemesin.
  static const _explainTimeout = Duration(seconds: 12);

  PermissionExplainer(this._feedback);

  Future<bool> ensure(Permission permission, String explanation) =>
      ensureAll([permission], explanation);

  /// Birbiriyle ilgili izinleri (örn. Bluetooth tarama + bağlanma) tek
  /// açıklamayla ister. Hepsi verildiyse true.
  Future<bool> ensureAll(List<Permission> permissions, String explanation) async {
    try {
      final missing = <Permission>[];
      for (final p in permissions) {
        final status = await p.status;
        if (!_ok(status)) missing.add(p);
      }
      if (missing.isEmpty) return true;

      for (final p in missing) {
        if (await p.status.isPermanentlyDenied) {
          await _feedback.say(Tr.permissionPermanentlyDenied);
          return false;
        }
      }

      await _feedback.say(explanation).timeout(_explainTimeout, onTimeout: () => false);
      final results = await missing.request();
      final granted = results.values.every(_ok);
      if (!granted) _feedback.say(Tr.permissionDenied);
      return granted;
    } catch (e) {
      // Plugin yok (testler) ya da platform desteklemiyor - akışı kilitleme.
      debugPrint('[Permissions] istenemedi: $e');
      return false;
    }
  }

  static bool _ok(PermissionStatus s) => s.isGranted || s.isLimited;

  /// Bildirim dinleyici erişimi (bkz. `NotificationAccess`) - normal
  /// `ensure`den farklı: sistem bir izin penceresi değil ayar ekranı açar,
  /// kullanıcı elle açıp geri döner. Zaten açıksa hiçbir şey sormaz. Kapalıysa
  /// açıklayıp ayarları açar; dönüşte etkin olup olmadığını çağıran taraf
  /// (ekrana her dönüldüğünde) tekrar [access.isEnabled] ile kontrol etmeli -
  /// burada senkron bir "verildi" cevabı yok.
  Future<bool> ensureNotificationAccess(
      NotificationAccess access, String explanation) async {
    if (await access.isEnabled()) return true;
    await _feedback.say(explanation).timeout(_explainTimeout, onTimeout: () => false);
    await access.openSettings();
    return false;
  }
}
