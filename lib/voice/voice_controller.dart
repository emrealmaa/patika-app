import 'package:flutter/foundation.dart';

import '../accessibility/feedback_hub.dart';
import '../ble/ble_command.dart';
import '../commands/voice_intent_classifier.dart';
import '../l10n/strings_tr.dart';
import '../settings/settings.dart';
import 'speech_input_service.dart';

/// Dinlemeyi kim başlattı - davranış aynı, sadece kayıt/teşhis için.
enum ListenSource { screen, glasses, gesture, tile, test }

enum VoicePhase { idle, preparing, listening, processing }

/// Tüm ekransız ve ekranlı tetikleyicilerin (gözlük butonu, baş sallama,
/// Konuş alanı, Hızlı Ayarlar karosu) geldiği TEK dinleme kapısı.
///
/// - Aynı çağrı dinleme sürerken gelirse dinlemeyi iptal eder (aç/kapat).
/// - Dinlemeden önce süren konuşmayı susturur: tetikleyiciyle araya girme
///   (barge-in). Kendi sesimizi de mikrofona kaydetmemiş oluruz.
/// - Kontrol komutları ("dur", "tekrar et", "ne yapabilirim") "Şunu
///   anladım" teyidi olmadan hemen uygulanır - aksi halde "tekrar et" o
///   teyit cümlesini tekrar ederdi.
class VoiceController extends ChangeNotifier {
  /// "Dinliyorum" duyurusu ile mikrofonun açılması arasındaki bekleme -
  /// TTS'in sesi mikrofona komut olarak girmesin. Kısa ses ~0,2 sn sürüyor.
  static const speechGap = Duration(milliseconds: 1200);
  static const earconGap = Duration(milliseconds: 400);

  /// "Şunu anladım" ile komutun uygulanması arası - teyit, sonucun
  /// duyurusuyla kesilmesin.
  static const confirmGap = Duration(milliseconds: 1200);

  final SpeechInput _speech;
  final FeedbackHub _feedback;
  final Future<bool> Function() _ensureMicPermission;
  final Future<void> Function(BleCommand command) _submit;
  final VoidCallback? _onListenStart;

  VoicePhase _phase = VoicePhase.idle;
  String? _lastHeard;
  ListenSource? _source;
  bool _micEverGranted = false;

  /// Mikrofon izni ilk kez alındığında - arka plan servisi mikrofon
  /// türüyle yeniden başlatılsın diye (Android 14 kuralı).
  final VoidCallback? onMicrophoneGranted;

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

  /// Dinlemeyi başlatır; zaten dinliyorsa iptal eder. Komut işlenirken
  /// gelen çağrılar yok sayılır.
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

    _source = source;
    debugPrint('[Voice] dinleme istendi: ${source.name}');
    _setPhase(VoicePhase.preparing);
    // Tetikleyiciyle araya girme: süren konuşma/eğitim hemen susar.
    _onListenStart?.call();
    _feedback.queue.stopAll();

    final granted = await _ensureMicPermission();
    if (_phase != VoicePhase.preparing) return;
    if (!granted) {
      _setPhase(VoicePhase.idle);
      _feedback.signal(FeedbackEvent.error, text: Tr.micPermissionDenied);
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
      _setPhase(VoicePhase.idle);
      _feedback.signal(FeedbackEvent.error, text: Tr.speechUnavailable);
      return;
    }

    _feedback.signal(FeedbackEvent.listening, statusText: Tr.listening);
    await Future.delayed(_listenGap);
    // Beklerken iptal edildiyse dinlemeye başlama.
    if (_phase != VoicePhase.preparing) return;

    _setPhase(VoicePhase.listening);
    debugPrint('[Voice] mikrofon açılıyor');
    await _speech.listen(
      onFinal: _onFinal,
      onError: _onError,
      onDone: () => _onError(Tr.didNotHear),
      silenceTimeout: _settings.silenceTimeout,
    );
  }

  /// Dinlemeyi sonuç üretmeden iptal eder.
  Future<void> cancel() async {
    if (_phase != VoicePhase.preparing && _phase != VoicePhase.listening) return;
    _setPhase(VoicePhase.idle);
    await _speech.cancel();
    _feedback.signal(FeedbackEvent.listenEnded, statusText: Tr.listenCancelled);
  }

  Future<void> _onFinal(String text) async {
    if (_phase != VoicePhase.listening) return;
    if (text.isEmpty) {
      _onError(Tr.didNotHear);
      return;
    }

    _lastHeard = text;
    _setPhase(VoicePhase.processing);
    final command = classifyVoiceCommand(text);

    if (!command.intent.isControl) {
      _feedback.signal(FeedbackEvent.understood, text: Tr.heard(text));
      await Future.delayed(confirmGap);
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
    _setPhase(VoicePhase.idle);
    _feedback.signal(FeedbackEvent.notUnderstood, text: message);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}
