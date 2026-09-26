import '../../commands/action_result.dart';
import '../../commands/intent.dart';
import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../dialog_manager.dart';
import '../reply_parser.dart';
import 'recipient_flow.dart';

/// MESAJ: "Mesaj gönder" -> "Kime?" -> "Ayşe" -> "Ne yazayım?" -> dikte ->
/// "Ayşe Demir'e: '...'. Göndereyim mi?" -> "evet" -> SMS ekranı metin dolu
/// açılır (gönder tuşuna kullanıcı basar - Faz 4'te bayrak açıksa doğrudan).
/// Geri okumada "düzelt" yeniden dikte, "tekrar oku" metni tekrar okur.
class MessageFlow extends RecipientFlow {
  final Future<ActionResult> Function(ContactEntry contact, String body) _send;

  String? _body;
  bool _reviewing = false;

  MessageFlow(super.spoken, super.contacts, this._send);

  @override
  PatikaIntent get intent => PatikaIntent.mesaj;

  @override
  String get askNamePrompt => Tr.dialogWhoToMessage;

  @override
  String notFoundPrompt(String spoken) =>
      Tr.dialogNotFound(RecipientFlow.acc(spoken), Tr.dialogWhoToMessage);

  String get _reviewPrompt => Tr.dialogConfirmMessage(RecipientFlow.dat(contact!.displayName), _body!);

  AskStep _askBody() {
    _reviewing = false;
    resetUnclear();
    return const AskStep(Tr.dialogWhatToWrite, dictation: true);
  }

  @override
  Future<DialogStep> onContactChosen(ContactEntry contact) async => _askBody();

  @override
  Future<DialogStep> onLaterReply(String text) async {
    if (!_reviewing) {
      final body = text.trim();
      if (body.isEmpty) return unclear(Tr.dialogDidNotHear, Tr.dialogWhatToWrite, dictation: true);
      _body = body;
      _reviewing = true;
      resetUnclear();
      return AskStep(_reviewPrompt);
    }

    switch (parseReview(text)) {
      case ReviewAction.send:
        return FinishStep(await _send(contact!, _body!));
      case ReviewAction.edit:
        return _askBody();
      case ReviewAction.reread:
        return AskStep(_reviewPrompt);
      case ReviewAction.cancel:
        return const CancelStep();
      case ReviewAction.unknown:
        return unclear(Tr.dialogReviewHint, _reviewPrompt);
    }
  }
}
