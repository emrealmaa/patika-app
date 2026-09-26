import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// NAVİGASYON niyeti. phone_bridge.py'deki simüle "NAVIGATE" eyleminin
/// gerçek karşılığı.
///
/// Google Maps'in evrensel yönlendirme URL şeması kullanılıyor
/// (`google.com/maps/dir/?api=1&destination=<serbest metin>`) - bu, ayrı bir
/// geocoding API anahtarı gerektirmeden Google'ın kendi sunucusunda serbest
/// metni (örn. "Kadıköy iskelesi") konuma çözmesini sağlıyor. Yüklüyse
/// Google Maps uygulamasını, değilse tarayıcıyı açar - hem Android hem iOS'ta
/// çalışır.
class NavigationHandler {
  Future<ActionResult> handle(String? entity) async {
    if (entity == null) {
      return ActionResult.fail(Tr.navNoTarget);
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': entity,
      'travelmode': 'walking',
    });

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      return ActionResult.fail(Tr.mapsFailed);
    }
    return ActionResult.ok(Tr.navStarted(entity), detail: Tr.navStartedDetail);
  }
}
