import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Kısa durum sesleri. Dosyalar `tool/generate_earcons.dart` ile üretiliyor.
enum Earcon {
  listenStart('earcons/listen_start.wav'),
  listenEnd('earcons/listen_end.wav'),
  success('earcons/success.wav'),
  error('earcons/error.wav');

  final String asset;
  const Earcon(this.asset);
}

abstract class EarconPlayer {
  Future<void> play(Earcon earcon);
}

class AudioplayersEarconPlayer implements EarconPlayer {
  /// TTS ile AYNI kanal (navigasyon rehberliği -> pratikte medya sesi):
  /// konuşmayı duyan kullanıcı kısa sesi de mutlaka duyar, ikisi aynı ses
  /// tuşuyla ayarlanır. Önceki "sistem sesi" (assistanceSonification) kanalı
  /// sistem sesleri kısık telefonlarda tamamen sessizdi - kullanıcı
  /// dinlemenin başladığını hiç duymuyordu (Galaxy S24 FE'de sistem sesi
  /// 0/15, medya 12/15 iken doğrulandı). Müziği durdurmaz, kısa süre kısar.
  static final _context = AudioContext(
    android: AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  final Map<Earcon, AudioPlayer> _players = {};

  @override
  Future<void> play(Earcon earcon) async {
    try {
      final player = _players[earcon] ??= await _createPlayer();
      await player.stop();
      await player.play(AssetSource(earcon.asset));
    } catch (e) {
      debugPrint('[Earcon] çalınamadı: $e');
    }
  }

  // Oyuncular ilk kullanımda oluşturuluyor - testlerde (plugin yokken)
  // hiç kullanılmayan bir kısa ses platform çağrısı yapmasın diye.
  Future<AudioPlayer> _createPlayer() async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setAudioContext(_context);
    await player.setReleaseMode(ReleaseMode.stop);
    return player;
  }
}
