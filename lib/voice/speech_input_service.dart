import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/strings_tr.dart';
import 'recognition_session.dart';

/// Konuşma tanıma soyutlaması - VoiceController bunu kullanıyor, testlerde
/// sahte bir uygulama veriliyor.
abstract class SpeechInput {
  Future<bool> init();
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout,
    bool dictation,
  });
  Future<void> cancel();
}

/// Telefonun yerleşik konuşma tanıma motoru (Android SpeechRecognizer / iOS
/// SFSpeechRecognizer) üzerinde ince bir sarmalayıcı. Ekranlar
/// `speech_to_text` paketini doğrudan bilmiyor - BLE servislerindeki
/// soyutlamayla aynı ruh.
///
/// Gizlilik notu: Android'de varsayılan olarak ses Google sunucularında
/// işlenir. `onDevice: true` tamamen cihazda çalışır ama Türkçe çevrimdışı
/// paket kurulu değilse dinleme başarısız olur - bu yüzden kapalı.
class SpeechInputService implements SpeechInput {
  static const localeId = 'tr_TR';

  final SpeechToText _speech = SpeechToText();

  /// Süren dinleme oturumu. Her oturum kendi nesnesi: önceki oturumdan geç
  /// gelen sonuç (gerçek cihazda görüldü) kapanmış eski oturuma gider ve
  /// yok sayılır, yenisine karışmaz.
  RecognitionSession? _session;

  /// Motoru hazırlar ve (ilk seferde) mikrofon/konuşma tanıma iznini ister.
  /// İzin reddedildiyse ya da cihazda tanıma motoru yoksa false döner.
  @override
  Future<bool> init() {
    return _speech.initialize(
      // Debug derlemede eklentinin kendi günlüğü de açık: tanıyıcının ne
      // gönderdiğini logcat'te görmek için (gerçek cihaz teşhisi).
      debugLogging: kDebugMode,
      onError: (SpeechRecognitionError e) {
        // Ham kod teşhis için loga (kullanıcıya Türkçe açıklaması gidiyor).
        debugPrint('[Speech] hata: ${e.errorMsg} (kalıcı: ${e.permanent})');
        _session?.onError(describeError(e.errorMsg));
      },
      onStatus: (status) {
        debugPrint('[Speech] durum: $status');
        if (status == SpeechToText.doneStatus) _session?.onDone();
      },
    );
  }

  /// Tek bir komut dinler. Kullanıcı sustuğunda motor dinlemeyi kendisi
  /// bitirir ve [onFinal] tanınan metinle bir kez çağrılır; hiçbir şey
  /// tanınmadıysa (sessizlik, ağ yok vb.) onun yerine [onError] ya da
  /// [onDone] çağrılır. Sonucun toplanması ve geç gelen sonucun beklenmesi
  /// [RecognitionSession]'da.
  ///
  /// Ara sonuçlar BİLEREK açık: güncel Google Konuşma Hizmetleri (Android
  /// 13+, "segmentli" oturum) tanıdığı metni "final" etiketiyle
  /// göndermeyebiliyor - ara sonuçlar kapalıyken eklenti bu metni sessizce
  /// atıyor ve her komut "Sizi duyamadım" oluyordu (Galaxy S24 FE /
  /// Android 16'da doğrulandı).
  /// [silenceTimeout]: kullanıcı bu kadar susunca dinleme biter (ayarlardan).
  @override
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout = const Duration(seconds: 3),
    bool dictation = false,
  }) async {
    _session?.close();
    final session = RecognitionSession(onFinal: onFinal, onError: onError, onDone: onDone);
    _session = session;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        debugPrint('[Speech] sonuç: "${r.recognizedWords}" (final: ${r.finalResult})');
        session.onResult(r.recognizedWords, isFinal: r.finalResult);
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        // Dikte: serbest metin (mesaj gövdesi) - daha uzun dinleme.
        listenMode: dictation ? ListenMode.dictation : ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        listenFor: Duration(seconds: dictation ? 30 : 15),
        pauseFor: silenceTimeout,
      ),
    );
  }

  /// Sonuç üretmeden dinlemeyi iptal eder.
  @override
  Future<void> cancel() {
    _session?.close();
    _session = null;
    return _speech.cancel();
  }

  /// Platform hata kodlarını (kullanıcıya gösterilmek için değil) sesli
  /// duyurulabilir Türkçe cümlelere çevirir.
  static String describeError(String code) {
    switch (code) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return Tr.didNotHear;
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
        return Tr.speechNeedsInternet;
      case 'error_insufficient_permissions':
      case 'error_permission':
        return Tr.micPermissionDenied;
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return Tr.turkishUnavailable;
      case 'error_busy':
        return Tr.recognizerBusy;
      default:
        return Tr.recognitionFailed;
    }
  }
}
