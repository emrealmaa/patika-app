import 'package:flutter/foundation.dart';

import '../accessibility/feedback_hub.dart';
import '../ble/ble_command.dart';
import '../commands/intent.dart';
import '../commands/voice_intent_classifier.dart';
import '../l10n/strings_tr.dart';
import '../settings/settings.dart';
import 'dialog_manager.dart';
import 'speech_input_service.dart';

/// Dinlemeyi kim başlattı - davranış aynı, sadece kayıt/teşhis için.
enum ListenSource { screen, glasses, gesture, tile, test, dialog, sos }

enum VoicePhase { idle, preparing, listening, processing }

/// Tüm ekransız ve ekranlı tetikleyicilerin (gözlük butonu, baş sallama,
/// Konuş alanı, Hızlı Ayarlar karosu) geldiği TEK dinleme kapısı.
///
/// - Aynı çağrı dinleme sürerken gelirse dinlemeyi iptal eder (aç/kapat).
/// - Dinlemeden önce süren konuşmayı susturur: tetikleyiciyle araya girme
///   (barge-in). Kendi sesimizi de mikrofona kaydetmemiş oluruz.
/// - Telefon eylemi başlatan komutlar (ARA, MESAJ, NAVİGASYON) çok adımlı
///   diyaloğa gider ve eylemden önce onay sorar ("Ahmet Yılmaz'ı arayayım
///   mı?"); yanlış duyulmuş bir isim/yer yanlış eyleme yol açmasın. Bilgi,
///   ayar ve kontrol komutları hemen uygulanır.
class VoiceController extends ChangeNotifier {
  /// "Dinliyorum" duyurusu ile mikrofonun açılması arasındaki bekleme -
  /// TTS'in sesi mikrofona komut olarak girmesin. Kısa ses ~0,2 sn sürüyor.
  static const speechGap = Duration(milliseconds: 1200);
  static const earconGap = Duration(milliseconds: 400);

  /// Dikte (mesaj metni): insanlar cümle kurarken duraksar - dinleme
  /// ayardaki sessizlik süresinden bu kadar daha geç bitsin.
  static const dictationExtraSilence = Duration(seconds: 2);

  /// Diyalog cevabı ("... arayayım mı?"): soruyu dinleyip düşünmek zaman
  /// alır; gerçek cihazda cevaplar 3 sn'lik pencerede kaçtı (hiçbir şey
  /// tanınmadan tam 3,0 sn'de kapandı). Komutlarda pencere değişmez.
  static const dialogReplyExtraSilence = Duration(milliseconds: 1500);

  final SpeechInput _speech;
  final FeedbackHub _feedback;
  final Future<bool> Function() _ensureMicPermission;
  final Future<void> Function(BleCommand command) _submit;
  final VoidCallback? _onListenStart;

  /// Etkin bir diyalog varsa tanınan metin sınıflandırıcıya değil ona gider.
  DialogManager? dialog;

  VoicePhase _phase = VoicePhase.idle;
  String? _lastHeard;
  ListenSource? _source;
  bool _micEverGranted = false;

  /// Mikrofon izni ilk kez alındığında - arka plan servisi mikrofon
  /// türüyle yeniden başlatılsın diye (Android 14 kuralı).
  final VoidCallback? onMicrophoneGranted;

  /// Acil durum geri sayımında (Faz 7) açılan SESSİZ dinleme oturumu: kısa ses
  /// ya da "Dinliyorum" yok, sonuç sınıflandırıcıya/diyaloğa değil buraya gider
  /// ve oturum sonuçsuz bitse bile "anlayamadım" denmez. Yalnızca iptal /
  /// gönder komutları için (bkz. `classifySosVoice`).
  void Function(String text)? onSosSpeech;
  bool _sosSession = false;

  VoiceController({
    required SpeechInput speech,
    required FeedbackHub feedback,
    required Future<bool> Function() ensureMicPermission,
    required Future<void> Function(BleCommand command) submit,
    VoidCallback? onListenStart,
    this.onMicrophoneGranted,
  })  : _speech = speech,
        _feedback = feedback,
        _ensureMicPermission = ensureMicPermission,
        _submit = submit,
        _onListenStart = onListenStart;

  VoicePhase get phase => _phase;
  String? get lastHeard => _lastHeard;
  ListenSource? get source => _source;
  bool get isActive => _phase != VoicePhase.idle;

  Settings get _settings => _feedback.settings;

  Duration get _listenGap =>
      _settings.feedbackMode == FeedbackMode.speech ? speechGap : earconGap;

  void _setPhase(VoicePhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// Dinlemeyi başlatır; zaten dinliyorsa iptal eder (diyalog sürüyorsa
  /// diyaloğu da). Komut işlenirken gelen çağrılar yok sayılır. Diyalog bir
  /// cevap beklerken dokunmak "şimdi cevap veriyorum" demektir: dinleme
  /// açılır, cevap diyaloğa gider.
  Future<void> startListening(ListenSource source) async {
    switch (_phase) {
      case VoicePhase.processing:
        return;
      case VoicePhase.preparing:
      case VoicePhase.listening:
        await cancel();
        return;
      case VoicePhase.idle:
        break;
    }
    // Tetikleyiciyle araya girme: süren konuşma/eğitim hemen susar.
    _onListenStart?.call();
    _feedback.queue.stopAll();
    await _listen(
      source,
      dictation: dialog?.expectsDictation ?? false,
      dialogReply: dialog?.active ?? false,
    );
  }

  /// Acil durum geri sayımı sürerken sessizce dinler ("iptal" için). Başka bir
  /// dinleme/işlem sürüyorsa hiçbir şey yapmaz; çağıran (geri sayım tiki) bir
  /// saniye sonra yeniden dener.
  Future<void> listenForSos() async {
    if (_phase != VoicePhase.idle) return;
    await _listen(ListenSource.sos, dictation: false, dialogReply: false, sos: true);
  }

  /// Diyalog sorusu bittiğinde: tetikleyici beklemeden cevabı dinler.
  Future<void> listenForReply({required bool dictation}) async {
    if (_phase != VoicePhase.idle) return;
    await _listen(ListenSource.dialog, dictation: dictation, dialogReply: true);
  }

  Future<void> _listen(
    ListenSource source, {
    required bool dictation,
    required bool dialogReply,
    bool sos = false,
  }) async {
    _source = source;
    _sosSession = sos;
    debugPrint('[Voice] dinleme istendi: ${source.name}${dictation ? " (dikte)" : ""}');
    _setPhase(VoicePhase.preparing);

    final granted = await _ensureMicPermission();
    if (_phase != VoicePhase.preparing) return;
    if (!granted) {
      _sosSession = false;
      _setPhase(VoicePhase.idle);
      // SOS geri sayımında izin penceresi/uyarı konuşması araya girmez.
      if (!sos) _feedback.signal(FeedbackEvent.error, text: Tr.micPermissionDenied);
      return;
    }
    if (!_micEverGranted) {
      _micEverGranted = true;
      onMicrophoneGranted?.call();
    }

    final ready = await _speech.init();
    if (_phase != VoicePhase.preparing) return;
    if (!ready) {
      debugPrint('[Voice] tanıyıcı hazır değil');
      _sosSession = false;
      _setPhase(VoicePhase.idle);
      if (!sos) _feedback.signal(FeedbackEvent.error, text: Tr.speechUnavailable);
      return;
    }

    // SOS oturumunda dinleme sesi/sözü yok: geri sayım bipleriyle karışmasın.
    if (!sos) {
      _feedback.signal(FeedbackEvent.listening, statusText: Tr.listening);
      await Future.delayed(_listenGap);
    }
    // Beklerken iptal edildiyse dinlemeye başlama.
    if (_phase != VoicePhase.preparing) return;

    _setPhase(VoicePhase.listening);
    debugPrint('[Voice] mikrofon açılıyor');
    await _speech.listen(
      onFinal: _onFinal,
      onError: _onError,
      onDone: () => _onError(Tr.didNotHear),
      silenceTimeout: _settings.silenceTimeout +
          (dictation
              ? dictationExtraSilence
              : dialogReply
                  ? dialogReplyExtraSilence
                  : Duration.zero),
      dictation: dictation,
    );
  }

  /// Dinlemeyi sonuç üretmeden iptal eder. Diyalog sürüyorsa onu da bitirir
  /// ("dinlerken dokunmak = iptal"); iptal duyurusunu diyalog yapar.
  Future<void> cancel() async {
    if (_phase != VoicePhase.preparing && _phase != VoicePhase.listening) return;
    final wasSos = _sosSession;
    _sosSession = false;
    _setPhase(VoicePhase.idle);
    await _speech.cancel();
    if (wasSos) return; // sessiz SOS oturumu: "dinleme iptal edildi" denmez
    final dialog = this.dialog;
    if (dialog != null && dialog.active) {
      dialog.cancel();
    } else {
      _feedback.signal(FeedbackEvent.listenEnded, statusText: Tr.listenCancelled);
    }
  }

  Future<void> _onFinal(String text) async {
    if (_phase != VoicePhase.listening) return;
    if (text.isEmpty) {
      _onError(Tr.didNotHear);
      return;
    }

    _lastHeard = text;

    // Acil durum dinlemesi: metin yalnızca SOS iptal/gönder komutu olarak
    // yorumlanır; başka hiçbir komut çalışmaz.
    if (_sosSession) {
      _sosSession = false;
      _setPhase(VoicePhase.idle);
      onSosSpeech?.call(text);
      return;
    }

    final dialog = this.dialog;
    if (dialog != null && dialog.active) {
      if (classifyControl(text, dictation: dialog.expectsDictation) == PatikaIntent.sos) {
        // Güvenlik her zaman önce: diyalog sessizce biter, SOS işlenir.
        dialog.cancel(null);
      } else {
        // Cevap sınıflandırıcıya gitmez ("Ahmet", "evet", mesaj metni).
        // Boşta kalıyoruz ki diyalog sıradaki soruda dinlemeyi açabilsin.
        _setPhase(VoicePhase.idle);
        await dialog.reply(text);
        return;
      }
    }

    _setPhase(VoicePhase.processing);
    var command = classifyVoiceCommand(text);

    if (command.intent == PatikaIntent.bilinmiyor) {
      // Duyulan metin "anlayamadım" cümlesine ekleniyor (kullanıcı neyin
      // yanlış duyulduğunu öğrenir).
      command = BleCommand(intent: PatikaIntent.bilinmiyor, entity: text);
    }

    try {
      // Sonuç duyurusunu AppState yapıyor (diğer kaynaklarla aynı yol).
      await _submit(command);
    } finally {
      _setPhase(VoicePhase.idle);
    }
  }

  void _onError(String message) {
    if (_phase != VoicePhase.listening) return;
    debugPrint('[Voice] dinleme bitti, sonuç yok: $message');
    final wasSos = _sosSession;
    _sosSession = false;
    _setPhase(VoicePhase.idle);
    // SOS geri sayımında sessizlik/hata konuşulmaz; geri sayım tiki yeniden açar.
    if (wasSos) return;

    final dialog = this.dialog;
    if (dialog != null && dialog.active) {
      if (message == Tr.didNotHear) {
        // Sessizlik: diyalog soruyu bir kez tekrarlar, ikincide iptal eder.
        _feedback.signal(FeedbackEvent.notUnderstood);
        dialog.noReply();
      } else {
        // Ağ yok, izin yok vb.: diyalog sürdürülemez.
        dialog.cancel(message);
      }
      return;
    }
    _feedback.signal(FeedbackEvent.notUnderstood, text: message);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}
