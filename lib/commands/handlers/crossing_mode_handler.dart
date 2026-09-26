import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// GECIS_MODU niyeti. Python tarafında bu, crossing_mode.py'deki ağır
/// görü-tabanlı (trafik ışığı rengi + araç izleme) bir durum makinesini
/// başlatıyor - "telefon eylemi" değil, Katman 1 güvenlik mantığının bir
/// parçası.
///
/// KAPSAM DIŞI (v1): bu görevin kapsamı BLE + telefon eylemi yönlendirme
/// idi. crossing_mode.py'nin Dart'a taşınması (kamera + görü işleme
/// gerektirir) çok daha büyük, bağımsız bir iş kalemi (bkz.
/// patika_app/TODO.md). Şimdilik sadece niyeti tanıyıp bilgilendirici bir
/// sonuç döndürüyor, çökmüyor.
class CrossingModeHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail(Tr.crossingNotReady);
  }
}
