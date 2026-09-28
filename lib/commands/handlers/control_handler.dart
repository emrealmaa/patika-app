import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../intent.dart';

/// Kontrol niyetlerinin dokunduğu uygulama işlevleri - AppState uyguluyor.
/// Handler bu sayede duyuru kuyruğunu/eğitimi doğrudan bilmiyor ve testte
/// sahte bir uygulamayla denenebiliyor.
abstract class ControlActions {
  /// Konuşmayı keser, sırayı boşaltır, süren eğitimi durdurur.
  void stopEverything();

  /// Son duyuruyu tekrar okur; tekrar edilecek bir şey yoksa false.
  bool repeatLast();

  void startTutorial();

  /// Acil durum (SOS) geri sayımını başlatır (Faz 7). Sesli "yardım"/"imdat"/
  /// "acil durum" buraya gelir; söylenecekleri SOS denetleyicisi kendisi söyler.
  void triggerSos();
}

/// Evrensel konuşma kontrolü (DUR / TEKRAR / KOMUTLAR / EĞİTİM / SOS).
class ControlHandler {
  final ControlActions? _actions;

  ControlHandler([this._actions]);

  Future<ActionResult> handle(PatikaIntent intent) async {
    final actions = _actions;
    switch (intent) {
      case PatikaIntent.dur:
        actions?.stopEverything();
        return ActionResult.silentOk('Durduruldu');
      case PatikaIntent.tekrar:
        final repeated = actions?.repeatLast() ?? false;
        return repeated
            ? ActionResult.silentOk('Tekrar edildi')
            : ActionResult.fail(Tr.nothingToRepeat);
      case PatikaIntent.komutlar:
        return ActionResult.ok(Tr.helpShort, detail: Tr.helpDetail);
      case PatikaIntent.egitim:
        actions?.startTutorial();
        return ActionResult.silentOk('Eğitim başlatıldı');
      case PatikaIntent.sos:
        // Ne ses ne titreşim ne kayıt: SOS kendi geri bildirimini verir
        // (geri sayım bipi, kritik öncelikli duyurular); ayrıca "başarılı"
        // kısa sesi çalmasın.
        actions?.triggerSos();
        return ActionResult.handedOff('SOS');
      default:
        return ActionResult.fail(Tr.unknownCommand);
    }
  }
}
