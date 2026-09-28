import 'dart:async';

import '../../l10n/strings_tr.dart';
import '../../navigation/navigation_backend.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/navigation_flow.dart';
import '../action_result.dart';

/// NAVİGASYON niyeti (phone_bridge.py'deki simüle "NAVIGATE" eyleminin
/// gerçek karşılığı). Çok adımlı sesli akışı ([NavigationFlow]) başlatır:
/// yer eksikse sorar, belirsizse "hangisi?" der, başlamadan önce onay alır.
/// Sonucu (navigasyon başladı / harita açıldı) diyalog bitince AppState
/// kaydedip duyurur.
///
/// Google anahtarı yoksa ya da konum hazır değilse [NavigationBackend] eski
/// davranışa (Google Haritalar yürüyüş yönlendirmesi) düşer; sesli akış
/// aynıdır. Diyalog ya da arka uç verilmemişse (yalnızca testlerdeki
/// varsayılan yönlendirici) hiçbir şey açılmaz.
class NavigationHandler {
  final DialogManager? _dialogs;
  final NavigationBackend? _backend;

  NavigationHandler({DialogManager? dialogs, NavigationBackend? backend})
      : _dialogs = dialogs,
        _backend = backend;

  Future<ActionResult> handle(String? entity) async {
    final dialogs = _dialogs, backend = _backend;
    if (dialogs == null || backend == null) return ActionResult.fail(Tr.mapsFailed);

    // Diyalog dakikalar sürebilir; router'ı bekletmiyoruz.
    unawaited(dialogs.start(NavigationFlow(entity, backend)));
    return ActionResult.handedOff('Navigasyon diyaloğu başladı');
  }
}
