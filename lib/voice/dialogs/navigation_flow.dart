import '../../commands/intent.dart';
import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../navigation/navigation_backend.dart';
import '../dialog_manager.dart';
import '../reply_parser.dart';

/// NAVİGASYON: "Kadıköy iskelesine götür" -> (yer eksikse "Nereye gitmek
/// istiyorsunuz?") -> (birden çok yer: "Hangisi?") -> "Kadıköy İskelesi,
/// 1,2 kilometre, yaklaşık 15 dakika. Başlayayım mı?" -> "evet" -> navigasyon.
///
/// Bu onay sorusu, Faz 2'deki "Şunu anladım" teyidinin yerini alıyor: yanlış
/// duyulan bir yer, yürünecek yanlış bir rota demek. Yedek akışta (anahtar
/// yok ya da konum hazır değil) soru "X için harita uygulamasını açayım mı?"
/// olur ve nedeni söylenir (bkz. [NavigationBackend]).
class NavigationFlow extends DialogFlow {
  /// Anlaşılamayan cevap bu kadar kez ipucuyla tekrar sorulur, sonra iptal.
  static const maxUnclear = 2;

  final String? _spoken;
  final NavigationBackend _backend;

  NavigationFlow(this._spoken, this._backend);

  var _stage = _Stage.name;
  NavResolution? _resolution;
  NavPlace? _place;
  NavPreview? _preview;
  int _notFound = 0;
  int _unclear = 0;

  @override
  PatikaIntent get intent => PatikaIntent.navigasyon;

  @override
  String? get entityLabel => _place?.name ?? _spoken;

  @override
  Future<DialogStep> begin() async {
    final spoken = _spoken;
    if (spoken == null) return const AskStep(Tr.navAskDestination);
    return _resolve(spoken);
  }

  @override
  Future<DialogStep> onReply(String text) async {
    switch (_stage) {
      case _Stage.name:
        return _resolve(text);
      case _Stage.choose:
        final places = _resolution!.places;
        final index = parseChoice(text, _asContacts(places));
        if (index == null) return _unclearStep(Tr.navChoiceHint, _choosePrompt(places));
        return _chosen(places[index]);
      case _Stage.confirm:
        switch (parseYesNo(text)) {
          case YesNo.yes:
            return FinishStep(await _backend.start(_preview!));
          case YesNo.no:
            return const CancelStep();
          case YesNo.unknown:
            return _unclearStep(Tr.dialogYesNoHint, _preview!.prompt);
        }
    }
  }

  Future<DialogStep> _resolve(String spoken) async {
    final resolution = await _backend.resolve(spoken);
    _resolution = resolution;
    final places = resolution.places;

    if (places.isEmpty) {
      if (++_notFound > 1) return CancelStep(Tr.navPlaceNotFoundFinal(spoken));
      _stage = _Stage.name;
      return AskStep(Tr.navPlaceNotFound(spoken));
    }
    if (places.length == 1) return _chosen(places.single);

    _stage = _Stage.choose;
    _unclear = 0;
    return AskStep(_choosePrompt(places));
  }

  Future<DialogStep> _chosen(NavPlace place) async {
    _place = place;
    final preview = await _backend.preview(place, _resolution!);
    _preview = preview;
    _stage = _Stage.confirm;
    _unclear = 0;
    return AskStep(preview.prompt);
  }

  String _choosePrompt(List<NavPlace> places) =>
      Tr.navChoosePlace([for (final p in places) p.name]);

  /// Ortak cevap ayrıştırıcısı ("ikinci", "sonuncu", ad) kişi adayları
  /// bekliyor; yer adları aynı biçime sarılıyor.
  static List<ContactEntry> _asContacts(List<NavPlace> places) => [
        for (var i = 0; i < places.length; i++) ContactEntry('$i', places[i].name, const []),
      ];

  DialogStep _unclearStep(String hint, String prompt) {
    if (++_unclear >= maxUnclear) return const CancelStep(Tr.dialogNotUnderstood);
    return AskStep('$hint $prompt');
  }
}

enum _Stage { name, choose, confirm }
