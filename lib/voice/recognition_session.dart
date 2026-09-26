import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tek bir dinleme oturumunun sonucunu toplayıp BİR KEZ teslim eden saf
/// mantık (eklentiden bağımsız - zamanlama fake_async ile test ediliyor).
///
/// Gerçek cihazda görülen iki durum:
/// - Güncel Google Konuşma Hizmetleri metni "final" etiketiyle
///   göndermeyebiliyor: en son tanınan metin saklanır, oturum bitince o
///   teslim edilir.
/// - Metin "bitti" sinyalinden SONRA gelebiliyor (Galaxy S24 FE: "done"dan
///   170 ms sonra "hava nasıl" geldi ve kullanıcı konuştuğu halde "Sizi
///   duyamadım" duydu). Bu yüzden bitti/hata anında henüz hiç metin yoksa
///   [lateResultGrace] kadar geç sonuç beklenir; gelirse o teslim edilir.
class RecognitionSession {
  static const lateResultGrace = Duration(seconds: 1);

  final void Function(String text) _onFinal;
  final void Function(String message) _onError;
  final void Function() _onDone;

  String _lastWords = '';
  bool _finished = false;
  Timer? _grace;

  RecognitionSession({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
  })  : _onFinal = onFinal,
        _onError = onError,
        _onDone = onDone;

  bool get finished => _finished;

  void onResult(String words, {required bool isFinal}) {
    if (_finished) return;
    final text = words.trim();
    if (text.isEmpty) return;
    _lastWords = text;
    // Geç sonuç bekleniyorsa ilk gelen metin yeterli.
    if (isFinal || _grace != null) _deliver(text);
  }

  /// Tanıyıcı "bitti" dedi.
  void onDone() {
    if (_finished || _deliverLastWords()) return;
    _waitForLateResult(_onDone);
  }

  /// Tanıyıcı hata verdi ([message] kullanıcıya okunacak Türkçe metin).
  /// Tanınmış bir metin varken gelen "eşleşme yok/zaman aşımı" hatası o
  /// metni geçersiz kılmaz.
  void onError(String message) {
    if (_finished || _deliverLastWords()) return;
    _waitForLateResult(() => _onError(message));
  }

  /// Oturum sonuç üretmeden kapatıldı (iptal): artık hiçbir şey teslim edilmez.
  void close() {
    _finished = true;
    _grace?.cancel();
    _grace = null;
  }

  void _deliver(String text) {
    if (_finished) return;
    close();
    _onFinal(text);
  }

  bool _deliverLastWords() {
    if (_lastWords.isEmpty) return false;
    debugPrint('[Speech] final gelmedi, son tanınan metin kullanılıyor');
    _deliver(_lastWords);
    return true;
  }

  /// İlk bitiş sinyali (hata ya da bitti) kazanır; sonrakiler yok sayılır.
  void _waitForLateResult(void Function() giveUp) {
    if (_grace != null) return;
    _grace = Timer(lateResultGrace, () {
      _grace = null;
      if (_finished) return;
      close();
      giveUp();
    });
  }
}
