import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// HAVA niyeti. Python tarafında bu, phone_bridge'e hiç uğramadan
/// hava_durumu.py (wttr.in + IP tabanlı konum) ile gerçek veri çekiyor -
/// "bir telefon eylemi" değil, bir API çağrısı + TTS.
///
/// KAPSAM DIŞI (v1): bu görev "gözlükten gelen komutları telefon eylemine
/// yönlendirme" (BLE + call/sms/navigasyon/müzik/haber gibi gerçek telefon
/// işlevleri) kapsamındaydı - wttr.in entegrasyonunu Dart'a taşımak ayrı,
/// bağımsız bir iş kalemi (bkz. patika_app/TODO.md). Şimdilik sadece niyeti
/// tanıyıp bilgilendirici bir sonuç döndürüyor, çökmüyor.
class WeatherHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail(Tr.weatherNotReady);
  }
}
