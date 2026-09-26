import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// HABER niyeti. phone_bridge.py'deki simüle "NEWS" eyleminin gerçek
/// karşılığı.
///
/// KAPSAM DIŞI (v1): hangi haber kaynağının kullanılacağı henüz netleşmedi -
/// gerçek entegrasyon ayrı bir görev (bkz. patika_app/TODO.md). Şimdilik
/// sadece niyeti tanıyıp bilgilendirici bir sonuç döndürüyor, çökmüyor.
class NewsHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail(Tr.newsNotReady);
  }
}
