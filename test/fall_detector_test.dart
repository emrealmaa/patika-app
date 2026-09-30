import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_config.dart';
import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/motion_sample.dart';
import 'package:patika_app/fall/synthetic_signals.dart';

/// Faz 7c-1: düşme dedektörünün saf mantığı. Eşikler TAHMİNİ (bkz.
/// `fall_config.dart`); bu testler eşiklerin doğru olduğunu değil, dedektörün
/// eşikleri tutarlı uyguladığını kilitler.
void main() {
  List<FallEvaluation> run(List<MotionSample> samples, {FallConfig config = const FallConfig()}) =>
      FallDetector(config: config).addAll(samples);

  FallEvaluation single(List<MotionSample> samples) {
    final out = run(samples);
    expect(out, hasLength(1), reason: '$out');
    return out.single;
  }

  const sec = Duration(seconds: 1);
  Duration ms(int v) => Duration(milliseconds: v);

  /// Dik duruş → düşüş → darbe → [after] yönünde hareketsiz. Gürültüsüz.
  SignalBuilder fall({
    Duration freeFall = const Duration(milliseconds: 300),
    double peakG = 3.0,
    GVector after = lyingFlat,
    Duration before = const Duration(seconds: 2),
  }) {
    return SignalBuilder(noiseG: 0)
      ..hold(before, upright)
      ..freeFall(freeFall)
      ..impact(peakG, dir: after)
      ..hold(sec * 8, after);
  }

  group('hazır senaryolar', () {
    test('gerçekçi düşme -> aday, özet değerler dolu', () {
      final e = single(syntheticScenario(SyntheticScenario.realisticFall));
      expect(e.outcome, FallOutcome.candidate);
      expect(e.freeFallMs, inInclusiveRange(300, 360));
      expect(e.peakG, closeTo(3.5, 0.1));
      expect(e.orientationDegrees, closeTo(90, 5));
      expect(e.stillnessStdG, lessThan(0.05));
    });

    test('düştü, hemen alındı -> hareket', () {
      final e = single(syntheticScenario(SyntheticScenario.droppedAndPickedUp));
      expect(e.outcome, FallOutcome.movement);
      expect(e.orientationDegrees, closeTo(90, 5));
      expect(e.stillnessStdG, greaterThanOrEqualTo(0.1));
    });

    test('sert oturma (serbest düşüş yok) -> değerlendirme hiç başlamaz', () {
      expect(run(syntheticScenario(SyntheticScenario.hardSit)), isEmpty);
    });

    test('düşüş, yumuşak iniş -> darbe yok (kayda girmeyecek tür)', () {
      final e = single(syntheticScenario(SyntheticScenario.fallNoImpact));
      expect(e.outcome, FallOutcome.noImpact);
      expect(e.outcome.reachedImpact, isFalse);
      expect(e.orientationDegrees, isNull);
      expect(e.stillnessStdG, isNull);
    });

    test('darbe var, telefon yine dik -> yön değişmedi', () {
      final e = single(syntheticScenario(SyntheticScenario.impactNoOrientationChange));
      expect(e.outcome, FallOutcome.noOrientationChange);
      expect(e.orientationDegrees, lessThan(10));
    });

    test('20 sn yürüme -> hiçbir değerlendirme', () {
      expect(run(syntheticScenario(SyntheticScenario.walking)), isEmpty);
    });

    test('gerçekçi düşme farklı gürültü tohumlarıyla da aday', () {
      for (var seed = 1; seed <= 20; seed++) {
        final out = run(syntheticScenario(SyntheticScenario.realisticFall, seed: seed));
        expect(out.map((e) => e.outcome), [FallOutcome.candidate], reason: 'tohum $seed');
      }
    });

    test('yalnızca darbe adımına ulaşanlar reachedImpact', () {
      expect(FallOutcome.values.where((o) => o.reachedImpact),
          [FallOutcome.noOrientationChange, FallOutcome.movement, FallOutcome.candidate]);
    });
  });

  group('eşik sınırları (gürültüsüz)', () {
    test('serbest düşüş: 60 ms sayılmaz, 100 ms sayılır', () {
      expect(run(fall(freeFall: ms(60)).samples), isEmpty);
      expect(single(fall(freeFall: ms(100)).samples).outcome, FallOutcome.candidate);
    });

    test('serbest düşüş 1 sn\'den uzunsa sessizce elenir (yeni düşüş de başlamaz)', () {
      expect(run(fall(freeFall: ms(1200)).samples), isEmpty);
    });

    test('darbe: 2,4 g yok, 2,6 g var', () {
      expect(single(fall(peakG: 2.4).samples).outcome, FallOutcome.noImpact);
      expect(single(fall(peakG: 2.6).samples).outcome, FallOutcome.candidate);
    });

    test('yön değişimi: 40° yetmez, 50° yeter', () {
      final e40 = single(fall(after: tilted(40)).samples);
      expect(e40.outcome, FallOutcome.noOrientationChange);
      expect(e40.orientationDegrees, closeTo(40, 1));
      final e50 = single(fall(after: tilted(50)).samples);
      expect(e50.outcome, FallOutcome.candidate);
      expect(e50.orientationDegrees, closeTo(50, 1));
    });

    test('hareketsizlik: 0,1 g genlikli titreme hareketsiz, 0,2 g hareket', () {
      SignalBuilder shaking(double amplitude) => SignalBuilder(noiseG: 0)
        ..hold(sec * 2, upright)
        ..freeFall(ms(300))
        ..impact(3.0, dir: lyingFlat)
        ..oscillate(sec * 8, lyingFlat, amplitudeG: amplitude);
      expect(single(shaking(0.1).samples).outcome, FallOutcome.candidate);
      expect(single(shaking(0.2).samples).outcome, FallOutcome.movement);
    });

    test('eşikler FallConfig ile değiştirilebilir', () {
      final samples = fall(peakG: 2.4).samples;
      final out = run(samples, config: const FallConfig(impactAboveG: 2.0));
      expect(out.single.outcome, FallOutcome.candidate);
    });

    test('adımlar sırayla: yön değişmediyse hareket ölçülse de sonuç "yön değişmedi"', () {
      final b = SignalBuilder(noiseG: 0)
        ..hold(sec * 2, upright)
        ..freeFall(ms(300))
        ..impact(3.0)
        ..walk(sec * 8);
      final e = single(b.samples);
      expect(e.outcome, FallOutcome.noOrientationChange);
      expect(e.stillnessStdG, greaterThanOrEqualTo(0.1), reason: 'değer yine kaydedilir');
    });
  });

  group('düşme öncesi yön', () {
    test('dedektör yeni başladıysa (yetersiz geçmiş) açı ölçülmez, elenir', () {
      final e = single(fall(before: ms(200)).samples);
      expect(e.outcome, FallOutcome.noOrientationChange);
      expect(e.orientationDegrees, isNull);
    });
  });

  group('örnek kesintisi', () {
    test('değerlendirme sırasında kesinti -> değerlendirme atılır, sayılır', () {
      final b = SignalBuilder(noiseG: 0)
        ..hold(sec * 2, upright)
        ..freeFall(ms(300))
        ..impact(3.0, dir: lyingFlat)
        ..hold(ms(500), lyingFlat)
        ..gap(sec * 2)
        ..hold(sec * 8, lyingFlat);
      final d = FallDetector();
      expect(d.addAll(b.samples), isEmpty);
      expect(d.gapCount, 1);
      expect(d.evaluating, isFalse);
    });

    test('kesintiden hemen sonraki düşmede yön bilinmez', () {
      final b = SignalBuilder(noiseG: 0)
        ..hold(sec * 2, upright)
        ..gap(sec * 3)
        ..hold(ms(200), upright)
        ..freeFall(ms(300))
        ..impact(3.0, dir: lyingFlat)
        ..hold(sec * 8, lyingFlat);
      final d = FallDetector();
      final out = d.addAll(b.samples);
      expect(out.single.outcome, FallOutcome.noOrientationChange);
      expect(out.single.orientationDegrees, isNull);
      expect(d.gapCount, 1);
    });

    test('yinelenen ya da geri giden zaman yok sayılır', () {
      final d = FallDetector();
      d.add(const MotionSample(1000, 0, standardGravity, 0));
      expect(d.add(const MotionSample(1000, 0, 0, 0)), isNull);
      expect(d.add(const MotionSample(900, 0, 0, 0)), isNull);
      expect(d.evaluating, isFalse);
      expect(d.gapCount, 0);
    });
  });

  group('art arda', () {
    test('düşme, yürüme, düşme -> iki aday; değerlendirme bitince baştan başlar', () {
      final b = SignalBuilder(noiseG: 0)
        ..hold(sec * 2, upright)
        ..freeFall(ms(300))
        ..impact(3.0, dir: lyingFlat)
        ..hold(sec * 8, lyingFlat)
        ..walk(sec * 5)
        ..hold(sec * 2, upright)
        ..freeFall(ms(300))
        ..impact(3.0, dir: lyingFlat)
        ..hold(sec * 8, lyingFlat);
      final out = run(b.samples);
      expect(out.map((e) => e.outcome), [FallOutcome.candidate, FallOutcome.candidate]);
      expect(out[1].startMs, greaterThan(out[0].startMs));
    });
  });
}
