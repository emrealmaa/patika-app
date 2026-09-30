import '../../commands/action_result.dart';
import '../../commands/intent.dart';
import '../../commands/voice_intent_classifier.dart';
import '../../fall/fall_enable_session.dart';
import '../../fall/fall_open_text.dart';
import '../../l10n/strings_tr.dart';
import '../dialog_manager.dart';

/// "Düşme algılamayı aç": açık moda iki adımlı geçişin SES kanalı (Faz 7c-2,
/// karar 1). Tüm kurallar (kapılar, kanal kilidi, süre, bayrak) `FallEnableSession`'da;
/// bu sınıf yalnızca söyleneni ve sırayı yönetir.
///
/// 1. `begin`: kapılar tutmazsa nedeni söyler ve biter. Tutarsa uyarıyı
///    (ilk kez TAM, sonra kısa) + "anladım, aç deyin" cümlesini söyler, dinler.
/// 2. Cevap: yalnızca tüm cümle "anladım aç" kalıpları açar
///    ([classifyFallEnableConfirm]). "Evet", "tamam", tek başına "aç" açmaz:
///    bir kez ipucu verilir, ikinci yanlış cevapta açma iptal edilir.
///    Sessizlik `DialogManager`'da iki denemeden sonra iptal; her durumda açılmaz.
///
/// "Vazgeç"/"dur"/"iptal" `DialogManager` tarafından yakalanıp diyaloğu
/// bitirir; bekleyen açma kendi süre aşımında (120 sn) düşer ve ses kanalı
/// başka yoldan onaylanamaz (yalnızca bu akışın `onReply`'ı onaylar).
class FallEnableFlow extends DialogFlow {
  final FallEnableSession _session;

  /// Yanlış cevap sayısı: ilki ipucu, ikincisi iptal.
  int _misses = 0;

  FallEnableFlow(this._session);

  @override
  PatikaIntent get intent => PatikaIntent.dusme;

  @override
  String? get entityLabel => null;

  @override
  Future<DialogStep> begin() async {
    final result = await _session.begin(FallEnableChannel.voice);
    switch (result.kind) {
      case FallEnableBeginKind.blocked:
        return FinishStep(ActionResult.fail(fallOpenBlockText(result.gate!)));
      case FallEnableBeginKind.alreadyOn:
        return FinishStep(ActionResult.ok(Tr.fallOpenAlready));
      case FallEnableBeginKind.superseded:
        // Başka bir kanal/başlatma devraldı; bu diyalog sessizce bitsin.
        return const CancelStep(Tr.fallOpenNotEnabled);
      case FallEnableBeginKind.prompt:
        final warning = result.fullText ? Tr.fallOpenWarningFull : Tr.fallOpenWarningShort;
        final note = result.gateBypassed ? '${Tr.fallGateBypassedNote}. ' : '';
        return AskStep('$note$warning ${Tr.fallOpenConfirmInstruction}');
    }
  }

  @override
  Future<DialogStep> onReply(String text) async {
    if (!classifyFallEnableConfirm(text)) {
      _misses++;
      if (_misses >= 2) {
        _session.cancel();
        return const CancelStep(Tr.fallOpenNotEnabled);
      }
      return const AskStep(Tr.fallOpenConfirmHint);
    }

    final confirm = await _session.confirm(FallEnableChannel.voice);
    switch (confirm.kind) {
      case FallEnableConfirmKind.enabled:
        return FinishStep(ActionResult.ok(Tr.fallOpenEnabled));
      case FallEnableConfirmKind.expired:
        return FinishStep(ActionResult.fail(Tr.fallOpenExpired));
      case FallEnableConfirmKind.blocked:
        return FinishStep(ActionResult.fail(fallOpenBlockText(confirm.gate!)));
      case FallEnableConfirmKind.storageFailed:
        return FinishStep(ActionResult.fail(Tr.fallOpenStorageFailed));
      case FallEnableConfirmKind.noPending:
      case FallEnableConfirmKind.wrongChannel:
        return FinishStep(ActionResult.fail(Tr.fallOpenNotEnabled));
    }
  }
}
