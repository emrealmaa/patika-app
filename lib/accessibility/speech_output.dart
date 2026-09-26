import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Seslendirme motoru soyutlaması - [AnnouncementQueue] bunu kullanıyor,
/// testlerde sahte bir uygulama veriliyor.
abstract class SpeechOutput {
  /// Konuşma bitince (ya da [stop] ile kesilince) tamamlanır.
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> configure({required double rate, required double pitch});
}

/// Telefonun TTS motoru (Android TextToSpeech). Tüm duyurular buradan
/// geçiyor; TalkBack'e ayrıca duyuru gönderilmiyor (çift okuma olmasın
/// diye - TalkBack sadece ekrandaki Semantics etiketlerini okur).
class FlutterTtsOutput implements SpeechOutput {
  final _tts = FlutterTts();
  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= () async {
        await _tts.setLanguage('tr-TR');
        await _tts.awaitSpeakCompletion(true);
        if (Platform.isAndroid) {
          // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE: çalan müziği susturmak
          // yerine kısar, Bluetooth kulaklığa (earbud) yönlenir.
          await _tts.setAudioAttributesForNavigation();
        }
      }();

  @override
  Future<void> speak(String text) async {
    try {
      await _ensureInit();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS] konuşulamadı: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('[TTS] durdurulamadı: $e');
    }
  }

  @override
  Future<void> configure({required double rate, required double pitch}) async {
    try {
      await _ensureInit();
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
    } catch (e) {
      debugPrint('[TTS] ayarlanamadı: $e');
    }
  }
}
