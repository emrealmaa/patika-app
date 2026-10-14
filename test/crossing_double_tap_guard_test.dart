import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/navigation/guidance_engine.dart';

import 'navigation_fixtures.dart';
import 'test_harness.dart';

/// Madde 8: karşıya geçiş duraklamasında kazara çift dokunuş koruması.
/// Varsayılan 0 (eski davranış: çift dokunuş hemen devam ettirir). Koruma
/// açıkken ilk N saniyede çift dokunuş "son duyuruyu tekrarla"ya düşer; tek
/// dokunuş (dinleme -> SOS/sesli komut) ve uzun basış (SOS) HİÇ etkilenmez.
void main() {
  final t0 = DateTime(2026, 10, 14, 12);

  Harness harness(FakeAsync async, {Duration guard = Duration.zero}) => Harness(
        guidanceConfig: GuidanceConfig(crossingDoubleTapGuard: guard),
        navigationNow: () => t0.add(async.elapsed),
      );

  void toCrossing(Harness h, FakeAsync async) {
    h.app.navigation.start(testRoute());
    async.flushMicrotasks();
    for (final (x, y) in walkPath([(0, 0), (0, 200), (140, 200)])) {
      h.location.emit(enu(x, y), time: t0.add(async.elapsed));
      async.elapse(const Duration(seconds: 1));
      h.speakAll(async);
      if (h.app.navigation.isPausedForCrossing) break;
    }
    expect(h.app.navigation.isPausedForCrossing, isTrue);
  }

  void doubleTap(Harness h, FakeAsync async) {
    h.app.simulator!.injectButton(GlassesButton.doubleTap);
    h.speakAll(async);
  }

  test('varsayılan (koruma yok): çift dokunuş hemen devam ettirir', () {
    fakeAsync((async) {
      final h = harness(async);
      expect(const GuidanceConfig().crossingDoubleTapGuard, Duration.zero);
      toCrossing(h, async);
      doubleTap(h, async);
      expect(h.app.navigation.isPausedForCrossing, isFalse);
      h.dispose();
    });
  });

  test('koruma açık: ilk N sn çift dokunuş duraklamayı bitirmez, tekrar eder; sonra bitirir', () {
    fakeAsync((async) {
      final h = harness(async, guard: const Duration(seconds: 10));
      toCrossing(h, async);
      h.tts.spoken.clear();

      async.elapse(const Duration(seconds: 2));
      doubleTap(h, async);
      expect(h.app.navigation.isPausedForCrossing, isTrue);
      expect(h.tts.spoken.single, Tr.navCrossingPoint,
          reason: 'sessiz kalmaz: duraklamada olduğunu tekrar duyurur');

      async.elapse(const Duration(seconds: 9));
      doubleTap(h, async);
      expect(h.app.navigation.isPausedForCrossing, isFalse);
      h.dispose();
    });
  });

  test('koruma sürerken tek dokunuş yine dinler, uzun basış yine SOS', () {
    fakeAsync((async) {
      final h = harness(async, guard: const Duration(seconds: 30));
      toCrossing(h, async);
      h.app.simulator!.injectButton(GlassesButton.tap);
      async.elapse(const Duration(seconds: 1));
      expect(h.speech.listening, isTrue, reason: 'SOS ve sesli komut kavşakta erişilebilir');
      h.speech.say('yardım');
      h.speakAll(async);
      expect(h.tts.spoken.last, contains('Bu sürümde acil durum mesajı gönderilemiyor'),
          reason: 'sesli "yardım" kavşakta da SOS yoluna gider');
      h.speakAll(async);

      h.app.simulator!.injectButton(GlassesButton.longPress);
      h.speakAll(async);
      expect(h.tts.spoken.last, contains('Bu sürümde acil durum mesajı gönderilemiyor'));
      expect(h.app.navigation.isPausedForCrossing, isTrue);
      h.dispose();
    });
  });

  test('"geçtim" korumadan etkilenmez', () {
    fakeAsync((async) {
      final h = harness(async, guard: const Duration(seconds: 30));
      toCrossing(h, async);
      expect(h.app.navigation.resumeFromCrossing(), isTrue);
      expect(h.app.navigation.isPausedForCrossing, isFalse);
      h.dispose();
    });
  });
}
