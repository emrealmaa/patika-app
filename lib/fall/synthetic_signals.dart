import 'dart:math' as math;

import 'motion_sample.dart';

/// Yön vektörü, g biriminde (uzunluğu 1 olması beklenir).
typedef GVector = (double, double, double);

/// Telefon dik (ekran karşıya bakıyor, cepte ayakta): yerçekimi y ekseninde.
const GVector upright = (0, 1, 0);

/// Telefon yatay (yerde, sırtüstü): yerçekimi z ekseninde.
const GVector lyingFlat = (0, 0, 1);

/// Dik duruştan y-z düzleminde [degrees] kadar eğik yön.
GVector tilted(double degrees) {
  final r = degrees * math.pi / 180;
  return (0, math.cos(r), math.sin(r));
}

/// Sentetik ivmeölçer sinyali kurar (Faz 7c). Test Modu düğmeleri ve birim
/// testleri aynı üreticiyi kullanır. Gerçek düşme verisi DEĞİLDİR: yalnızca
/// dedektörün adımlarını sınamak için şematik biçimler.
///
/// Örnekleme varsayılanı 50 Hz (20 ms), `MotionProbe.kt` ile aynı. Gürültü
/// eksen başına ±[noiseG] g, sabit tohumla (tekrarlanabilir).
class SignalBuilder {
  final int periodMs;
  final double noiseG;
  final math.Random _rng;
  final samples = <MotionSample>[];
  int _t;
  GVector _last = upright;

  SignalBuilder({int startMs = 0, this.periodMs = 20, this.noiseG = 0.02, int seed = 1})
      : _t = startMs,
        _rng = math.Random(seed);

  /// Sıradaki örneğin zamanı.
  int get nowMs => _t;

  void _emit(GVector dir, double magnitudeG) {
    double n() => noiseG == 0 ? 0 : (_rng.nextDouble() * 2 - 1) * noiseG;
    samples.add(MotionSample(
      _t,
      (dir.$1 * magnitudeG + n()) * standardGravity,
      (dir.$2 * magnitudeG + n()) * standardGravity,
      (dir.$3 * magnitudeG + n()) * standardGravity,
    ));
    _t += periodMs;
  }

  int _count(Duration d) => math.max(1, d.inMilliseconds ~/ periodMs);

  /// Hareketsiz: [dir] yönünde 1 g.
  void hold(Duration d, GVector dir) {
    _last = dir;
    for (var i = 0; i < _count(d); i++) {
      _emit(dir, 1);
    }
  }

  /// Serbest düşüş: büyüklük [g] (neredeyse sıfır), yön son duruş.
  void freeFall(Duration d, {double g = 0.1}) {
    for (var i = 0; i < _count(d); i++) {
      _emit(_last, g);
    }
  }

  /// Darbe: üç örneklik tepe (yarım, tam, yarım), büyüklük en fazla [peakG].
  void impact(double peakG, {GVector? dir}) {
    final d = dir ?? _last;
    for (final frac in const [0.5, 1.0, 0.5]) {
      _emit(d, 1 + (peakG - 1) * frac);
    }
  }

  /// Salınım: [dir] yönünde büyüklüğü 1 ± [amplitudeG] olan [hz] frekanslı
  /// sinüs. Yürüme ~0,3 g / 2 Hz; titreme küçük genlik.
  void oscillate(Duration d, GVector dir, {required double amplitudeG, double hz = 2}) {
    _last = dir;
    final start = _t;
    for (var i = 0; i < _count(d); i++) {
      final sec = (_t - start) / 1000;
      _emit(dir, 1 + amplitudeG * math.sin(2 * math.pi * hz * sec));
    }
  }

  /// Yürüme (dik, 0,3 g genlik, 2 Hz). Büyüklük hiç serbest düşüş eşiğine inmez.
  void walk(Duration d) => oscillate(d, upright, amplitudeG: 0.3);

  /// Örnek gelmeyen boşluk (ekran kapalıyken CPU uykusu gibi).
  void gap(Duration d) => _t += d.inMilliseconds;
}

/// Test Modu'ndaki sentetik düğmeler ve testlerdeki hazır senaryolar.
enum SyntheticScenario {
  /// Dik duruş → düşüş → sert darbe → yerde hareketsiz. Beklenen: aday.
  realisticFall,

  /// Telefon düşer, yerde kısa kalır, alınıp yüründü. Beklenen: hareket.
  droppedAndPickedUp,

  /// Yürürken sert oturma: darbe var, serbest düşüş yok. Beklenen:
  /// değerlendirme hiç başlamaz.
  hardSit,

  /// Düşüş var, yumuşak iniş. Beklenen: darbe yok (kayda girmez).
  fallNoImpact,

  /// Düşüş + darbe, ama telefon yine dik. Beklenen: yön değişmedi.
  impactNoOrientationChange,

  /// Yalnızca yürüme. Beklenen: hiçbir değerlendirme.
  walking,
}

/// [scenario]'nun örneklerini [startMs]'den başlayarak üretir.
List<MotionSample> syntheticScenario(SyntheticScenario scenario, {int startMs = 0, int seed = 1}) {
  final b = SignalBuilder(startMs: startMs, seed: seed);
  const s = Duration(seconds: 1);
  switch (scenario) {
    case SyntheticScenario.realisticFall:
      b.hold(s * 2, upright);
      b.freeFall(const Duration(milliseconds: 350));
      b.impact(3.5, dir: lyingFlat);
      b.hold(s * 8, lyingFlat);
    case SyntheticScenario.droppedAndPickedUp:
      b.hold(s * 2, upright);
      b.freeFall(const Duration(milliseconds: 300));
      b.impact(3.0, dir: lyingFlat);
      b.hold(const Duration(milliseconds: 2500), lyingFlat);
      b.walk(s * 6);
    case SyntheticScenario.hardSit:
      b.walk(s * 3);
      b.impact(2.8);
      b.hold(s * 3, tilted(30));
    case SyntheticScenario.fallNoImpact:
      b.hold(s * 2, upright);
      b.freeFall(const Duration(milliseconds: 300));
      b.hold(s * 3, lyingFlat);
    case SyntheticScenario.impactNoOrientationChange:
      b.hold(s * 2, upright);
      b.freeFall(const Duration(milliseconds: 300));
      b.impact(3.0);
      b.hold(s * 8, upright);
    case SyntheticScenario.walking:
      b.walk(s * 20);
  }
  return b.samples;
}
