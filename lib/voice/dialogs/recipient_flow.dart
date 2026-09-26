import '../../commands/action_result.dart';
import '../../commands/contact_resolver.dart';
import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../l10n/turkish_suffix.dart';
import '../dialog_manager.dart';
import '../reply_parser.dart';

/// ARA ve MESAJ'ın ortak kişi belirleme adımları: kişi eksikse sor,
/// bulunamazsa bir kez daha sor, birden fazla eşleşmede "hangisi?".
/// Kişi belli olunca alt sınıfın [onContactChosen]'ı devralır.
abstract class RecipientFlow extends DialogFlow {
  /// Anlaşılamayan cevap bu kadar kez ipucuyla tekrar sorulur, sonra iptal.
  static const maxUnclear = 2;

  final String? _spoken;
  final ContactResolver _contacts;

  RecipientFlow(this._spoken, this._contacts);

  /// "Kimi arayayım?" / "Kime?"
  String get askNamePrompt;

  /// "X'i rehberde bulamadım. Kimi arayayım?"
  String notFoundPrompt(String spoken);

  Future<DialogStep> onContactChosen(ContactEntry contact);

  /// Kişi seçildikten sonraki adımların cevapları.
  Future<DialogStep> onLaterReply(String text);

  ContactEntry? contact;
  List<ContactEntry>? _choices;
  var _stage = _Stage.name;
  int _notFound = 0;
  int _unclear = 0;

  @override
  String? get entityLabel => contact?.displayName ?? _spoken;

  @override
  Future<DialogStep> begin() async {
    final spoken = _spoken;
    if (spoken == null) return AskStep(askNamePrompt);
    return _resolve(spoken);
  }

  @override
  Future<DialogStep> onReply(String text) async {
    switch (_stage) {
      case _Stage.name:
        return _resolve(text);
      case _Stage.choose:
        final choices = _choices!;
        final index = parseChoice(text, choices);
        if (index == null) return unclear(Tr.dialogChoiceHint, _choicePrompt(choices));
        return _chosen(choices[index]);
      case _Stage.later:
        return onLaterReply(text);
    }
  }

  Future<DialogStep> _resolve(String spoken) async {
    switch (await _contacts.resolve(spoken)) {
      case ContactFound(:final contact):
        return _chosen(contact);
      case ContactAmbiguous(:final candidates):
        _stage = _Stage.choose;
        _choices = candidates;
        _unclear = 0;
        return AskStep(_choicePrompt(candidates));
      case ContactNotFound():
        if (++_notFound > 1) return CancelStep(Tr.contactNotFound(spoken));
        _stage = _Stage.name;
        return AskStep(notFoundPrompt(spoken));
      case ContactPermissionDenied():
        return FinishStep(ActionResult.fail(Tr.contactsPermissionDenied));
    }
  }

  Future<DialogStep> _chosen(ContactEntry chosen) {
    contact = chosen;
    _stage = _Stage.later;
    _unclear = 0;
    return onContactChosen(chosen);
  }

  String _choicePrompt(List<ContactEntry> choices) =>
      Tr.dialogChoose([for (final c in choices) c.displayName]);

  /// Anlaşılamayan cevap: bir kez ipucuyla tekrar sor, ikincide iptal.
  DialogStep unclear(String hint, String prompt, {bool dictation = false}) {
    if (++_unclear >= maxUnclear) return const CancelStep(Tr.dialogNotUnderstood);
    return AskStep('$hint $prompt', dictation: dictation);
  }

  void resetUnclear() => _unclear = 0;

  /// "Ahmet Kaya'yı" gibi, soru cümleleri için.
  static String acc(String name) => accusative(name);
  static String dat(String name) => dative(name);
}

enum _Stage { name, choose, later }
