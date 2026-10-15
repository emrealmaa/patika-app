import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Seslendirme motoru soyutlaması - [AnnouncementQueue] bunu kullanıyor,
/// testlerde sahte bir uygulama veriliyor.
abstract class SpeechOutput {
  /// Konuşma bitince (ya da [stop] ile kesilince) tamamlanır.
  Future<void> speak(String text);
  Future<void> stop();
  /// [voiceId]: kullanıcının seçtiği ses ([VoiceInfo.id]); '' = otomatik.
  Future<void> configure({required double rate, required double pitch, String voiceId = ''});

  /// Ayarlar ve Test Modu için: telefondaki Türkçe sesler ve hangisinin seçildiği.
  Future<VoiceReport> voiceReport();
}

/// Bir TTS sesi (Test Modu'nda listelenir).
class VoiceInfo {
  final String name;
  final String locale;

  /// iOS: `premium`, `enhanced`, `default`; Android'de genelde boş.
  final String quality;

  /// iOS ses kimliği; Android'de yok.
  final String? identifier;

  const VoiceInfo({required this.name, required this.locale, this.quality = '', this.identifier});

  /// Ayarda saklanan anahtar: kimlik, yoksa ad.
  String get id => identifier ?? name;
}

/// Ses seçiminin sonucu: [voices] yalnızca Türkçe sesler; [selected] null ise
/// motorun varsayılan sesi kullanılıyor. [totalVoices] tüm dillerdeki ses
/// sayısı (liste boş geliyorsa bunu ayırt etmek için).
class VoiceReport {
  final List<VoiceInfo> voices;
  final VoiceInfo? selected;
  final int totalVoices;

  const VoiceReport({this.voices = const [], this.selected, this.totalVoices = 0});
}

/// Telefonun TTS motoru (Android TextToSpeech). Tüm duyurular buradan
/// geçiyor; TalkBack'e ayrıca duyuru gönderilmiyor (çift okuma olmasın
/// diye - TalkBack sadece ekrandaki Semantics etiketlerini okur).
class FlutterTtsOutput implements SpeechOutput {
  final _tts = FlutterTts();
  Future<void>? _init;
  List<dynamic> _voices = const [];
  VoiceReport _report = const VoiceReport();

  /// Son [configure]; [speak] bunu bekler ki ayarlardaki ses önizlemesi
  /// eski sesle başlamasın.
  Future<void> _config = Future.value();

  /// Uygulanan ses tercihi ('' = otomatik); null = henüz uygulanmadı.
  String? _appliedVoiceId;

  Future<void> _ensureInit() => _init ??= () async {
        await _tts.setLanguage('tr-TR');
        await _tts.awaitSpeakCompletion(true);
        final raw = await _tts.getVoices;
        _voices = raw is List ? raw : const [];
        _report = VoiceReport(voices: voicesFor(_voices, 'tr'), totalVoices: _voices.length);
        if (Platform.isAndroid) {
          // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE: çalan müziği susturmak
          // yerine kısar, Bluetooth kulaklığa (earbud) yönlenir.
          await _tts.setAudioAttributesForNavigation();
        }
      }();

  /// iOS varsayılan olarak en basit Türkçe sesi kullanır: kullanıcı ses
  /// seçtiyse onu, seçmediyse en kaliteli Türkçe sesi kullan. Siri sesleri
  /// üçüncü taraf uygulamalara açık değil, listede görünmez. Android'de
  /// motorun varsayılan sesi kalır.
  Future<void> _applyVoice(String voiceId) async {
    if (!Platform.isIOS || voiceId == _appliedVoiceId) return;
    _appliedVoiceId = voiceId;
    final choice = chooseVoice(_voices, 'tr', voiceId);
    VoiceInfo? selected;
    if (choice != null && await _tts.setVoice(choice) == 1) {
      selected = VoiceInfo(
        name: choice['name']!,
        locale: choice['locale']!,
        quality: choice['quality'] ?? '',
        identifier: choice['identifier'],
      );
    }
    _report = VoiceReport(voices: _report.voices, selected: selected, totalVoices: _report.totalVoices);
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _ensureInit();
      await _config;
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
  Future<VoiceReport> voiceReport() async {
    try {
      await _ensureInit();
      await _config;
    } catch (e) {
      debugPrint('[TTS] ses listesi alınamadı: $e');
    }
    return _report;
  }

  @override
  Future<void> configure({required double rate, required double pitch, String voiceId = ''}) =>
      _config = () async {
        try {
          await _ensureInit();
          await _applyVoice(voiceId);
          await _tts.setSpeechRate(rate);
          await _tts.setPitch(pitch);
        } catch (e) {
          debugPrint('[TTS] ayarlanamadı: $e');
        }
      }();
}

/// Kullanıcının seçtiği ses ([voiceId], [VoiceInfo.id]) listede varsa o;
/// yoksa (otomatik ya da ses silinmiş) [pickBestVoice].
Map<String, String>? chooseVoice(List<dynamic> voices, String languageCode, String voiceId) {
  if (voiceId.isNotEmpty) {
    for (final v in voices) {
      if (v is! Map || v['name'] == null || v['locale'] == null) continue;
      if ((v['identifier'] ?? v['name']).toString() != voiceId) continue;
      final match = pickBestVoice([v], languageCode);
      if (match != null) return match;
    }
  }
  return pickBestVoice(voices, languageCode);
}

/// `getVoices` çıktısından dili [languageCode] olan sesler.
List<VoiceInfo> voicesFor(List<dynamic> voices, String languageCode) => [
      for (final v in voices)
        if (v is Map &&
            v['name'] != null &&
            v['locale'] != null &&
            v['locale'].toString().split(RegExp('[-_]')).first.toLowerCase() == languageCode)
          VoiceInfo(
            name: v['name'].toString(),
            locale: v['locale'].toString(),
            quality: v['quality']?.toString() ?? '',
            identifier: v['identifier']?.toString(),
          ),
    ];

/// [voices] içinden dili [languageCode] olan en kaliteli sesi seçer
/// (premium > enhanced > default); Türkçe ses yoksa null. Eşitlikte
/// listedeki ilk ses kalır. Dönen harita `FlutterTts.setVoice`'a uygun:
/// `name`, `locale` ve (varsa) `identifier`, `quality`.
Map<String, String>? pickBestVoice(List<dynamic> voices, String languageCode) {
  const rank = {'premium': 2, 'enhanced': 1};
  Map<String, String>? best;
  var bestRank = -1;
  for (final v in voices) {
    if (v is! Map) continue;
    final name = v['name']?.toString();
    final locale = v['locale']?.toString();
    if (name == null || locale == null) continue;
    final lang = locale.split(RegExp('[-_]')).first.toLowerCase();
    if (lang != languageCode) continue;
    final r = rank[v['quality']?.toString()] ?? 0;
    if (r > bestRank) {
      bestRank = r;
      best = {
        'name': name,
        'locale': locale,
        if (v['identifier'] != null) 'identifier': v['identifier'].toString(),
        if (v['quality'] != null) 'quality': v['quality'].toString(),
      };
    }
  }
  return best;
}
