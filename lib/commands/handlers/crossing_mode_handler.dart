import '../../l10n/strings_tr.dart';
import '../../navigation/navigation_session.dart';
import '../action_result.dart';

/// GECIS_MODU niyeti. Python tarafında bu, crossing_mode.py'deki ağır
/// görü-tabanlı (trafik ışığı rengi + araç izleme) bir durum makinesini
/// başlatıyor - "telefon eylemi" değil, Katman 1 güvenlik mantığının bir
/// parçası.
///
/// KAPSAM DIŞI (v1): crossing_mode.py'nin Dart'a taşınması (kamera + görü
/// işleme gerektirir) çok daha büyük, bağımsız bir iş kalemi (bkz.
/// patika_app/TODO.md). Şimdilik niyeti tanıyıp bilgilendirici bir sonuç
/// döndürüyor, çökmüyor.
///
/// Tek gerçek etkisi (Faz 6): açık bir navigasyon varsa onu duraklatır.
/// Geçiş kararı Kavşak Geçiş Asistanına aittir; navigasyon bu sırada kendi
/// başına hiçbir şey söylememeli.
class CrossingModeHandler {
  final NavigationSession? _navigation;

  CrossingModeHandler([this._navigation]);

  Future<ActionResult> handle(String? entity) async {
    final paused = _navigation?.pauseForCrossing() ?? false;
    return ActionResult.fail(paused ? Tr.navCrossingModeNotReady : Tr.crossingNotReady);
  }
}
