import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/strings_tr.dart';

/// Konuşma tanıma soyutlaması - VoiceController bunu kullanıyor, testlerde
/// sahte bir uygulama veriliyor.
abstract class SpeechInput {
  Future<bool> init();
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout,
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
  void Function(String text)? _onFinal;
  void Function(String message)? _onError;
  void Function()? _onDone;

  /// Oturumda tanınan en son metin (ara sonuçlar dahil) ve oturumun
  /// sonucunun zaten teslim edilip edilmediği - bkz. [listen].
  String _lastWords = '';
  bool _delivered = false;

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
        // Tanınmış bir metin varken gelen "eşleşme yok/zaman aşımı" hatası
        // o metni geçersiz kılmaz.
        if (_deliverLastWords()) return;
        _onError?.call(describeError(e.errorMsg));
      },
      onStatus: (status) {
        debugPrint('[Speech] durum: $status');
        if (status == SpeechToText.doneStatus) {
          if (_deliverLastWords()) return;
          _onDone?.call();
        }
      },
    );
  }

  /// Tek bir komut dinler. Kullanıcı sustuğunda motor dinlemeyi kendisi
  /// bitirir ve [onFinal] tanınan metinle (boş olabilir) bir kez çağrılır;
  ///
  /// Ara sonuçlar BİLEREK açık: güncel Google Konuşma Hizmetleri (Android
  /// 13+, "segmentli" oturum) tanıdığı metni "final" etiketiyle
  /// göndermeyebiliyor - ara sonuçlar kapalıyken eklenti bu metni sessizce
  /// atıyor ve her komut "Sizi duyamadım" oluyordu (Galaxy S24 FE /
  /// Android 16'da doğrulandı). Artık en son tanınan metin saklanıyor;
  /// "final" gelirse o, gelmeden oturum biterse saklanan metin teslim ediliyor.
  /// hata olursa (sessizlik, ağ yok vb.) onun yerine [onError] çağrılır.
  /// [onDone] her dinleme oturumunun sonunda (sonuç/hata sonrasında da)
  /// çağrılır - ikisi de gelmediyse çağıranın takılı kalmaması için.
  /// [silenceTimeout]: kullanıcı bu kadar susunca dinleme biter (ayarlardan).
  @override
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout = const Duration(seconds: 3),
  }) async {
    _onFinal = onFinal;
    _onError = onError;
    _onDone = onDone;
    _lastWords = '';
    _delivered = false;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        final words = r.recognizedWords.trim();
        debugPrint('[Speech] sonuç: "$words" (final: ${r.finalResult})');
        if (words.isNotEmpty) _lastWords = words;
        if (r.finalResult && words.isNotEmpty) _deliver(words);
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 15),
        pauseFor: silenceTimeout,
      ),
    );
  }

  /// Oturumun metnini bir kez teslim eder (final ya da saklanan son metin).
  void _deliver(String words) {
    if (_delivered) return;
    _delivered = true;
    _onFinal?.call(words);
  }

  /// Oturum "final" göndermeden bittiyse saklanan son metni teslim eder.
  /// Teslim edildiyse (ya da zaten edilmişse) true.
  bool _deliverLastWords() {
    if (_delivered) return true;
    if (_lastWords.isEmpty) return false;
    debugPrint('[Speech] final gelmedi, son tanınan metin kullanılıyor');
    _deliver(_lastWords);
    return true;
  }

  /// Sonuç üretmeden dinlemeyi iptal eder.
  @override
  Future<void> cancel() {
    _onFinal = null;
    _onError = null;
    _onDone = null;
    _delivered = true;
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
