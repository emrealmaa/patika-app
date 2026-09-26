import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/strings_tr.dart';

/// Telefonun yerleşik konuşma tanıma motoru (Android SpeechRecognizer / iOS
/// SFSpeechRecognizer) üzerinde ince bir sarmalayıcı. Ekranlar
/// `speech_to_text` paketini doğrudan bilmiyor - BLE servislerindeki
/// soyutlamayla aynı ruh.
///
/// Gizlilik notu: Android'de varsayılan olarak ses Google sunucularında
/// işlenir. `onDevice: true` tamamen cihazda çalışır ama Türkçe çevrimdışı
/// paket kurulu değilse dinleme başarısız olur - bu yüzden kapalı.
class SpeechInputService {
  static const localeId = 'tr_TR';

  final SpeechToText _speech = SpeechToText();
  void Function(String message)? _onError;
  void Function()? _onDone;

  /// Motoru hazırlar ve (ilk seferde) mikrofon/konuşma tanıma iznini ister.
  /// İzin reddedildiyse ya da cihazda tanıma motoru yoksa false döner.
  Future<bool> init() {
    return _speech.initialize(
      onError: (SpeechRecognitionError e) =>
          _onError?.call(describeError(e.errorMsg)),
      onStatus: (status) {
        if (status == SpeechToText.doneStatus) _onDone?.call();
      },
    );
  }

  /// Tek bir komut dinler. Kullanıcı sustuğunda motor dinlemeyi kendisi
  /// bitirir ve [onFinal] tanınan metinle (boş olabilir) bir kez çağrılır;
  /// hata olursa (sessizlik, ağ yok vb.) onun yerine [onError] çağrılır.
  /// [onDone] her dinleme oturumunun sonunda (sonuç/hata sonrasında da)
  /// çağrılır - ikisi de gelmediyse çağıranın takılı kalmaması için.
  /// [silenceTimeout]: kullanıcı bu kadar susunca dinleme biter (ayarlardan).
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout = const Duration(seconds: 3),
  }) async {
    _onError = onError;
    _onDone = onDone;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult) onFinal(r.recognizedWords.trim());
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenMode: ListenMode.confirmation,
        partialResults: false,
        cancelOnError: true,
        listenFor: const Duration(seconds: 15),
        pauseFor: silenceTimeout,
      ),
    );
  }

  /// Sonuç üretmeden dinlemeyi iptal eder.
  Future<void> cancel() {
    _onError = null;
    _onDone = null;
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
