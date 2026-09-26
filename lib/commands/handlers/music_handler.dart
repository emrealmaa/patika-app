import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// MÜZİK niyeti. phone_bridge.py'deki simüle "PLAY_MUSIC" eyleminin
/// gerçek karşılığı.
///
/// KAPSAM DIŞI (v1): hangi müzik servisinin kullanılacağı (Spotify/YouTube
/// Music/vb.) henüz netleşmedi - gerçek entegrasyon ayrı bir görev (bkz.
/// patika_app/TODO.md). Şimdilik sadece niyeti tanıyıp bilgilendirici bir
/// sonuç döndürüyor, çökmüyor.
class MusicHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail(Tr.musicNotReady);
  }
}
