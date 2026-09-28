import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Telefonun titreşim dili. Gözlükte titreşim motoru yok (tasarımdan
/// çıkarıldı), bu desenler yalnızca telefonda çalar.
enum HapticPatternId {
  connected,
  disconnected,
  batteryLow,
  listening,
  understood,
  notUnderstood,
  error,
  obstacle,
  incomingCall,
  incomingMessage,
}

/// Android titreşim deseni: [timings] "bekle, titret, bekle, titret..."
/// milisaniyeleri, [amplitudes] her dilimin genliği (0-255; bekleme
/// dilimleri 0). Desenler birbirinden sadece şiddetle değil RİTİMLE
/// ayrılıyor - hafif titreşim ayarında da ayırt edilebilsinler.
class HapticPattern {
  final List<int> timings;
  final List<int> amplitudes;

  const HapticPattern(this.timings, this.amplitudes);

  /// Genlikleri kullanıcı ayarıyla (0..1) ölçekler. 0 dışı her genlik en az
  /// 1 kalır - Android 0'ı "titreşme" sayar.
  HapticPattern scaled(double scale) => HapticPattern(
        timings,
        [
          for (final a in amplitudes)
            a == 0 ? 0 : (a * scale).round().clamp(1, 255),
        ],
      );

  Duration get totalDuration =>
      Duration(milliseconds: timings.fold(0, (sum, t) => sum + t));
}

abstract final class HapticPatterns {
  static const Map<HapticPatternId, HapticPattern> all = {
    // Yükselen iki vuruş: "bağlandı".
    HapticPatternId.connected: HapticPattern([0, 60, 80, 140], [0, 120, 0, 255]),
    // Alçalan iki uzun vuruş: "koptu".
    HapticPatternId.disconnected: HapticPattern([0, 220, 100, 220], [0, 255, 0, 110]),
    // Üç yavaş vuruş.
    HapticPatternId.batteryLow: HapticPattern([0, 150, 200, 150, 200, 150], [0, 180, 0, 180, 0, 180]),
    // Tek kısa tık.
    HapticPatternId.listening: HapticPattern([0, 40], [0, 200]),
    // İki hızlı tık.
    HapticPatternId.understood: HapticPattern([0, 40, 70, 40], [0, 200, 0, 200]),
    // Tek uzun vızıltı.
    HapticPatternId.notUnderstood: HapticPattern([0, 350], [0, 160]),
    // Üç hızlı güçlü vuruş.
    HapticPatternId.error: HapticPattern([0, 80, 50, 80, 50, 80], [0, 255, 0, 255, 0, 255]),
    // Tek vuruş; tekrar aralığını [obstacleInterval] belirler.
    HapticPatternId.obstacle: HapticPattern([0, 60], [0, 255]),
    // Çift-çift, aralarda duraklı: telefon zili gibi "brr-brr ... brr-brr".
    HapticPatternId.incomingCall:
        HapticPattern([0, 120, 100, 120, 400, 120, 100, 120], [0, 255, 0, 255, 0, 255, 0, 255]),
    // Tek orta uzunlukta vuruş: listening'in kısa tıkı ile notUnderstood'un
    // uzun vızıltısı arasında - gelen mesaj.
    HapticPatternId.incomingMessage: HapticPattern([0, 180], [0, 200]),
  };

  static HapticPattern of(HapticPatternId id) => all[id]!;

  static const obstacleFarMeters = 2.5;
  static const obstacleNearMeters = 0.4;
  static const obstacleMinInterval = Duration(milliseconds: 150);
  static const obstacleMaxInterval = Duration(milliseconds: 1000);

  /// Park sensörü mantığı: engel yaklaştıkça vuruşlar sıklaşır.
  /// [obstacleFarMeters] ve ötesinde null (titreşim yok), [obstacleNearMeters]
  /// ve berisinde en sık aralık (neredeyse sürekli).
  static Duration? obstacleInterval(double distanceMeters) {
    if (distanceMeters >= obstacleFarMeters) return null;
    if (distanceMeters <= obstacleNearMeters) return obstacleMinInterval;
    final t = (distanceMeters - obstacleNearMeters) /
        (obstacleFarMeters - obstacleNearMeters);
    final minMs = obstacleMinInterval.inMilliseconds;
    final maxMs = obstacleMaxInterval.inMilliseconds;
    return Duration(milliseconds: (minMs + t * (maxMs - minMs)).round());
  }
}

/// Titreşimin nereye verileceği soyutlaması (şimdilik yalnızca telefon;
/// testlerde sahtesi kullanılır).
abstract class HapticOutput {
  Future<void> play(HapticPatternId id, {required double scale});

  /// Engel mesafesine göre tekrarlayan titreşimi başlatır/günceller;
  /// null ya da uzak mesafe durdurur.
  void updateObstacle(double? distanceMeters, {required double scale});
}

class PhoneHaptics implements HapticOutput {
  Timer? _obstacleTimer;
  Duration? _obstacleInterval;
  double _obstacleScale = 1;
  bool? _hasVibrator;

  Future<bool> _canVibrate() async {
    try {
      return _hasVibrator ??= await Vibration.hasVibrator();
    } catch (e) {
      debugPrint('[Haptics] titreşim desteği sorgulanamadı: $e');
      return _hasVibrator = false;
    }
  }

  @override
  Future<void> play(HapticPatternId id, {required double scale}) =>
      _vibrate(HapticPatterns.of(id), scale);

  Future<void> _vibrate(HapticPattern pattern, double scale) async {
    if (scale <= 0 || !await _canVibrate()) return;
    final p = pattern.scaled(scale);
    try {
      await Vibration.vibrate(pattern: p.timings, intensities: p.amplitudes);
    } catch (e) {
      debugPrint('[Haptics] titreşim çalınamadı: $e');
    }
  }

  @override
  void updateObstacle(double? distanceMeters, {required double scale}) {
    final interval = distanceMeters == null
        ? null
        : HapticPatterns.obstacleInterval(distanceMeters);
    _obstacleScale = scale;
    if (interval == null || scale <= 0) {
      _obstacleTimer?.cancel();
      _obstacleTimer = null;
      _obstacleInterval = null;
      return;
    }
    if (interval == _obstacleInterval) return;
    _obstacleInterval = interval;
    _obstacleTimer?.cancel();
    _obstacleTimer = Timer.periodic(interval, (_) {
      _vibrate(HapticPatterns.of(HapticPatternId.obstacle), _obstacleScale);
    });
  }
}
