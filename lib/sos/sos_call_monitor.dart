import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SOS'un başlattığı aramanın sonu.
enum SosCallEnd {
  /// Arama sürdüğü gözlemlendi ve bitti: artık konuşmak güvenli.
  ended,

  /// Aramanın sürdüğü ya da bittiği doğrulanamadı: **konuşulmaz.** Özet
  /// yalnızca SOS geçmişine yazılır. Amaç: 112 (ya da acil kişi) görüşmesinin
  /// üstüne uygulama asla konuşmasın.
  unknown,
}

/// SOS'un başlattığı arama bitene kadar bekler. Arama sürerken uygulama
/// KONUŞMAZ (kullanıcı karşıdaki kişiyi duyuyor); geç kalan ya da başarısız
/// SMS sonuçları arama bittikten sonra özetlenir. Bitiş doğrulanamazsa
/// [SosCallEnd.unknown] döner ve hiç konuşulmaz.
abstract class SosCallMonitor {
  Future<SosCallEnd> untilCallEnds();
}

/// Aramanın sürdüğünü `AudioManager.getMode()` ile izler (izin gerekmez):
/// `MODE_IN_CALL` (telefon araması) ya da `MODE_IN_COMMUNICATION` (VoIP)
/// arama sürüyor demektir. Kanal `patika/audiomode` (bkz. `AudioModeProbe.kt`).
///
/// 1. Arama başladıktan sonra [startGrace] içinde ses modunun arama moduna
///    geçtiği görülmezse (OEM farkı, arama açılmadı, kanal yok) sonuç
///    **unknown**: konuşulmaz.
/// 2. Arama modu görüldükten sonra, modun art arda [stableReads] okumada arama
///    dışına dönmesi bekleniyor (anlık dalgalanma "bitti" sayılmasın).
/// 3. [maxDuration] aşılırsa **unknown**.
///
/// **Cihazda doğrulanmadı**: `MODE_IN_CALL`'ın Galaxy S24 FE / Android 16'da
/// giden aramanın çalma aşamasında da (karşı taraf açmadan) görülüp
/// görülmediği bekleyen telefon testlerinde (bkz. CLAUDE.md).
///
/// **Uygulamanın kendi sesi bu modu tetikler mi?** İncelendi (2026-09-28):
/// - `flutter_tts` yalnızca ses odağı ister (`requestAudioFocus`), modu
///   hiç değiştirmez. `audioplayers` (kısa sesler) `AudioManager`'a hiç
///   dokunmuyor. İkisi de bu sınıfı etkilemez.
/// - `speech_to_text` (STT) paketinin Android tarafı, eşleşmiş bir
///   Bluetooth kulaklık varsa `BluetoothHeadset.startVoiceRecognition()`
///   çağırıyor (kaynak: pub cache, `SpeechToTextPlugin.kt`,
///   `optionallyStartBluetooth`). Bu, Android'in ses alt sisteminde SCO
///   kanalını açar ve **muhtemelen** `AudioManager.getMode()`'u
///   `MODE_IN_COMMUNICATION`'a geçirir (Android'in genel SCO davranışı;
///   bu paketin kendisi `setMode` çağırmıyor, dolaylı). Bluetooth desteği
///   kasıtlı olarak KAPATILMADI (`SpeechToText.androidNoBluetooth`): planlı
///   donanımda gözlüğün açık-kulak kulaklığı Bluetooth ile bağlanacak ve
///   STT'nin oradan dinleyebilmesi asıl kullanım senaryosu.
///
/// **Neden tehlikeli değil (koddan):**
/// 1. Bu izleyici yalnızca **gerçek bir SOS araması başladıktan SONRA**
///    (`call.placed == true`) devreye giriyor - ortamdaki bir mod
///    değişikliğiyle KENDİLİĞİNDEN başlamıyor. Kendi STT'miz, hiç SOS
///    araması yokken modu değiştirse bile hiçbir şeyi tetiklemez.
/// 2. `SosPhase.sending` sırasında (arama sürerken) `VoiceController`
///    normal akışta yeni bir dinleme AÇMIYOR: gözlük dokunuşu o anda
///    `sos.cancel()`a gider (dinlemeye değil), "yardım" tekrarı geri
///    sayımda kapalı, çift baş sallama da aynı fazda devre dışı bırakıldı
///    (bkz. `AppState._onGesture`). Yani normal akışta kendi mikrofonumuz
///    gerçek aramayla ÇAKIŞMIYOR.
/// 3. Yine de kullanıcı elle (ekrandaki Konuş düğmesi, Hızlı Ayarlar
///    karosu) arama sürerken başka bir sesli komut başlatırsa: en kötü
///    ihtimalde `isCallMode` doğru ya da yanlış nedenle `true` kalmaya
///    devam eder, izleyici beklemeye devam eder - **asla erken "bitti"
///    sanıp konuşmaya başlamaz**, yalnızca özet daha geç (ya da hiç)
///    söylenir. Tasarımın güvenli yönü budur: şüphede sessiz kal.
/// 4. Adreslenmeyen ayrı bir risk: kendi STT'mizin Bluetooth SCO açması,
///    gerçek aramanın ses kanalıyla (aynı SCO bağlantısı) ÇAKIŞIP arama
///    sesinde bir kesinti/aksama yaratabilir - bu, tespit mantığından
///    bağımsız bir donanım/ses yönlendirme sorusu, cihazda doğrulanacak.
class AudioModeCallMonitor implements SosCallMonitor {
  static const _channel = MethodChannel('patika/audiomode');

  /// Android `AudioManager` sabitleri: 0 NORMAL, 1 RINGTONE, 2 IN_CALL,
  /// 3 IN_COMMUNICATION, 4 CALL_SCREENING, 5 CALL_REDIRECT, 6 COMMUNICATION_REDIRECT.
  /// 2 ve üstü "arama/iletişim sürüyor" sayılır (temkinli: şüphede sus).
  static bool isCallMode(int mode) => mode >= 2;

  final Future<int?> Function() _readMode;
  final Duration pollInterval;
  final Duration startGrace;
  final Duration maxDuration;
  final int stableReads;

  AudioModeCallMonitor({
    Future<int?> Function()? readMode,
    this.pollInterval = const Duration(seconds: 1),
    this.startGrace = const Duration(seconds: 30),
    this.maxDuration = const Duration(hours: 3),
    this.stableReads = 2,
  }) : _readMode = readMode ?? _readFromPlatform;

  static Future<int?> _readFromPlatform() async {
    try {
      return await _channel.invokeMethod<int>('mode');
    } catch (e) {
      debugPrint('[SOS] ses modu okunamadı: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<SosCallEnd> untilCallEnds() async {
    // 1) Arama moduna geçiş görülmeli.
    var waited = Duration.zero;
    while (true) {
      final mode = await _readMode();
      if (mode == null) return SosCallEnd.unknown;
      if (isCallMode(mode)) break;
      if (waited >= startGrace) return SosCallEnd.unknown;
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
    }

    // 2) Arama modundan çıkış art arda [stableReads] okumada görülmeli.
    var outside = 0;
    var elapsed = Duration.zero;
    while (elapsed < maxDuration) {
      await Future<void>.delayed(pollInterval);
      elapsed += pollInterval;
      final mode = await _readMode();
      if (mode == null) return SosCallEnd.unknown;
      outside = isCallMode(mode) ? 0 : outside + 1;
      if (outside >= stableReads) return SosCallEnd.ended;
    }
    return SosCallEnd.unknown;
  }
}
