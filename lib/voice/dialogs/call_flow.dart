import '../../commands/action_result.dart';
import '../../commands/intent.dart';
import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../dialog_manager.dart';
import '../reply_parser.dart';
import 'recipient_flow.dart';

/// ARA: "Ara" -> "Kimi arayayım?" -> (iki Ahmet: "Hangisi?") ->
/// "Ahmet Kaya'yı arayayım mı?" -> "evet" -> arama ekranı.
///
/// Onay sorusu, Faz 2'deki "Şunu anladım" teyidinin yerini alıyor: yanlış
/// duyulan bir isim yanlış kişinin aranmasına yol açmasın.
class CallFlow extends RecipientFlow {
  final Future<ActionResult> Function(ContactEntry contact) _dial;

  CallFlow(super.spoken, super.contacts, this._dial);

  @override
  PatikaIntent get intent => PatikaIntent.ara;

  @override
  String get askNamePrompt => Tr.dialogWhoToCall;

  @override
  String notFoundPrompt(String spoken) => Tr.dialogNotFound(RecipientFlow.acc(spoken), Tr.dialogWhoToCall);

  String get _confirmPrompt => Tr.dialogConfirmCall(RecipientFlow.acc(contact!.displayName));

  @override
  Future<DialogStep> onContactChosen(ContactEntry contact) async => AskStep(_confirmPrompt);

  @override
  Future<DialogStep> onLaterReply(String text) async {
    switch (parseYesNo(text)) {
      case YesNo.yes:
        return FinishStep(await _dial(contact!));
      case YesNo.no:
        return const CancelStep();
      case YesNo.unknown:
        return unclear(Tr.dialogYesNoHint, _confirmPrompt);
    }
  }
}
