import 'package:flutter/foundation.dart';

import '../accessibility/feedback_hub.dart';
import '../commands/action_result.dart';
import '../commands/intent.dart';
import '../commands/voice_intent_classifier.dart';
import '../l10n/strings_tr.dart';

/// Bir diyalog akışının sıradaki adımı.
sealed class DialogStep {
  const DialogStep();
}

/// Soru sor ve cevabı bekle. [dictation]: serbest metin (mesaj gövdesi) -
/// daha uzun sessizlik süresiyle dinlenir.
class AskStep extends DialogStep {
  final String prompt;
  final bool dictation;
  const AskStep(this.prompt, {this.dictation = false});
}

/// Diyalog bitti; sonuç kaydedilip duyurulur.
class FinishStep extends DialogStep {
  final ActionResult result;
  const FinishStep(this.result);
}

/// Diyalog iptal edildi; [message] duyurulur.
class CancelStep extends DialogStep {
  final String message;
  const CancelStep([this.message = Tr.dialogCancelled]);
}

/// Çok adımlı bir sesli akış (ARA, MESAJ). Yalnızca "sıradaki adım ne?"
/// sorusunu yanıtlar; soruyu söyletmek, dinlemek, "dur"/"tekrar et",
/// zaman aşımı [DialogManager]'ın işi.
abstract class DialogFlow {
  PatikaIntent get intent;

  /// İşlem geçmişinde görünecek kişi/yer (o ana kadar belli olan).
  String? get entityLabel;

  Future<DialogStep> begin();
  Future<DialogStep> onReply(String text);
}

/// Tek atımlık komutu çok adımlı konuşmaya çeviren durum makinesi:
/// bekleme -> (kişi eksik / seçim / onay / metin) -> tamamlandı / iptal.
///
/// - Soru bitince (say() sonuna kadar okununca) tetikleyici beklemeden
///   dinlemeyi açar. Soru okunurken kullanıcı dokunursa konuşma kesilir
///   (say() false döner) ve dinlemeyi dokunuşun kendisi başlatmış olur -
///   "dokunmak = şimdi cevap veriyorum".
/// - "dur/iptal/vazgeç" diyaloğu bitirir, "tekrar et" son soruyu tekrarlar
///   (her adımda). SOS'u VoiceController diyaloğa gelmeden yakalar.
/// - Cevap gelmezse soru bir kez tekrarlanır, ikincide iptal edilir.
class DialogManager extends ChangeNotifier {
  /// Art arda bu kadar cevapsız soru -> iptal.
  static const maxNoReply = 2;

  final FeedbackHub _feedback;
  final Future<void> Function({required bool dictation}) _listen;
  final void Function(DialogFlow flow, ActionResult result) _onFinished;

  DialogFlow? _flow;
  AskStep? _lastAsk;
  int _noReply = 0;
  int _generation = 0;

  DialogManager({
    required FeedbackHub feedback,
    required Future<void> Function({required bool dictation}) listen,
    required void Function(DialogFlow flow, ActionResult result) onFinished,
  })  : _feedback = feedback,
        _listen = listen,
        _onFinished = onFinished;

  bool get active => _flow != null;
  DialogFlow? get flow => _flow;

  /// Sıradaki cevap serbest metin mi (dikte)?
  bool get expectsDictation => _lastAsk?.dictation ?? false;

  /// Yeni bir diyalog başlatır (süren varsa sessizce bırakılır).
  Future<void> start(DialogFlow flow) async {
    _generation++;
    _flow = flow;
    _lastAsk = null;
    _noReply = 0;
    notifyListeners();
    debugPrint('[Dialog] başladı: ${flow.intent.name}');
    await _apply(await flow.begin());
  }

  /// Kullanıcının cevabı (VoiceController'dan, sınıflandırıcıya gitmeden).
  Future<void> reply(String text) async {
    final flow = _flow;
    if (flow == null) return;
    _noReply = 0;

    switch (classifyControl(text)) {
      case PatikaIntent.dur:
        return _end(const CancelStep());
      case PatikaIntent.tekrar:
        final ask = _lastAsk;
        if (ask != null) return _ask(ask);
        return;
      default:
        await _apply(await flow.onReply(text));
    }
  }

  /// Dinleme sonuç üretmeden bitti (sessizlik, zaman aşımı).
  Future<void> noReply() async {
    final ask = _lastAsk;
    if (_flow == null || ask == null) return;
    _noReply++;
    if (_noReply >= maxNoReply) return _end(const CancelStep(Tr.dialogTimedOut));
    await _ask(AskStep('${Tr.dialogDidNotHear} ${ask.prompt}', dictation: ask.dictation),
        remember: false);
  }

  /// Diyaloğu dışarıdan bitirir (dinlerken dokunuş, "dur" komutu, SOS).
  /// [message] null ise sessizce.
  void cancel([String? message = Tr.dialogCancelled]) {
    if (_flow == null) return;
    if (message == null) {
      _clear();
    } else {
      _end(CancelStep(message));
    }
  }

  Future<void> _apply(DialogStep step) async {
    switch (step) {
      case AskStep():
        await _ask(step);
      case FinishStep() || CancelStep():
        _end(step);
    }
  }

  Future<void> _ask(AskStep step, {bool remember = true}) async {
    if (remember) _lastAsk = step;
    final generation = _generation;
    // Birleştirme kuralı dışında: aynı soru ("tekrar oku", "tekrar et")
    // atılırsa dinleme hiç açılmaz ve diyalog asılı kalırdı.
    final spokenFully = await _feedback.say(step.prompt, dedupe: false);
    // Soru bu arada kesildiyse (dokunuş dinlemeyi zaten başlattı) ya da
    // diyalog bittiyse dinlemeyi açma.
    if (!spokenFully || generation != _generation || _flow == null) return;
    await _listen(dictation: step.dictation);
  }

  void _end(DialogStep step) {
    final flow = _flow;
    if (flow == null) return;
    _clear();
    final result = switch (step) {
      FinishStep(:final result) => result,
      CancelStep(:final message) => ActionResult.fail(message),
      AskStep() => ActionResult.fail(Tr.dialogCancelled),
    };
    debugPrint('[Dialog] bitti: ${flow.intent.name} (${result.success ? "tamam" : result.message})');
    _onFinished(flow, result);
  }

  void _clear() {
    _generation++;
    _flow = null;
    _lastAsk = null;
    notifyListeners();
  }
}
