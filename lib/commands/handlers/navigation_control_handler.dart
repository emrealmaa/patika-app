import '../../l10n/strings_tr.dart';
import '../../navigation/navigation_session.dart';
import '../action_result.dart';

/// Çalışan navigasyonu yöneten sesli komutlar (Faz 6): "navigasyonu bitir",
/// "ne kadar kaldı", "geçtim". Navigasyonu *başlatan* NAVİGASYON niyeti ayrı
/// ([NavigationHandler]). Oturum yoksa (testler) hepsi "açık navigasyon yok" der.
class NavigationControlHandler {
  final NavigationSession? _session;

  NavigationControlHandler([this._session]);

  Future<ActionResult> stop() async {
    final stopped = await _session?.stop() ?? false;
    return stopped ? ActionResult.ok(Tr.navStopped) : ActionResult.fail(Tr.navNotActive);
  }

  Future<ActionResult> remaining() async {
    final text = _session?.remainingText();
    return text == null ? ActionResult.fail(Tr.navNotActive) : ActionResult.ok(text);
  }

  /// "Geçtim": duraklamayı bitirir. Devam cümlesini ("Navigasyon devam
  /// ediyor" + varsa hemen ardındaki dönüş) oturumun kendisi söyler, bu
  /// yüzden başarı sonucu sessizdir - iki kez okunmasın.
  Future<ActionResult> crossed() async {
    final session = _session;
    if (session == null || !session.active) return ActionResult.fail(Tr.navNotActive);
    return session.resumeFromCrossing()
        ? ActionResult.silentOk('Navigasyon devam ediyor')
        : ActionResult.fail(Tr.navNotPaused);
  }
}
