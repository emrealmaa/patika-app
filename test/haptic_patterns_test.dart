import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/haptic_patterns.dart';

void main() {
  group('HapticPatterns', () {
    test('her desen tanımlı ve Android formatına uygun', () {
      for (final id in HapticPatternId.values) {
        final p = HapticPatterns.of(id);
        expect(p.timings.length, p.amplitudes.length, reason: '$id');
        expect(p.timings.length.isEven, isTrue, reason: '$id: bekle/titret çiftleri');
        for (var i = 0; i < p.amplitudes.length; i += 2) {
          expect(p.amplitudes[i], 0, reason: '$id: bekleme dilimi sessiz olmalı');
        }
        expect(p.amplitudes.every((a) => a >= 0 && a <= 255), isTrue, reason: '$id');
      }
    });

    test('desenler ritimle ayırt edilebilir (aynı zamanlama iki kez yok)', () {
      final timings = HapticPatternId.values
          .map((id) => HapticPatterns.of(id).timings.join(','))
          .toList();
      expect(timings.toSet().length, timings.length);
    });

    test('şiddet ölçekleme: 0 dışı genlik en az 1 kalır, beklemeler 0', () {
      final p = HapticPatterns.of(HapticPatternId.connected).scaled(0.001);
      expect(p.amplitudes, [0, 1, 0, 1]);
      final full = HapticPatterns.of(HapticPatternId.connected).scaled(1);
      expect(full.amplitudes, HapticPatterns.of(HapticPatternId.connected).amplitudes);
    });
  });

  group('engel aralığı (park sensörü)', () {
    test('uzakta titreşim yok', () {
      expect(HapticPatterns.obstacleInterval(2.5), isNull);
      expect(HapticPatterns.obstacleInterval(10), isNull);
    });

    test('çok yakında en sık aralık', () {
      expect(HapticPatterns.obstacleInterval(0.4), HapticPatterns.obstacleMinInterval);
      expect(HapticPatterns.obstacleInterval(0.1), HapticPatterns.obstacleMinInterval);
    });

    test('yaklaştıkça aralık kısalır', () {
      Duration? previous;
      for (var d = 2.4; d > 0.4; d -= 0.2) {
        final interval = HapticPatterns.obstacleInterval(d)!;
        if (previous != null) {
          expect(interval < previous, isTrue, reason: '$d m');
        }
        previous = interval;
      }
    });
  });
}
