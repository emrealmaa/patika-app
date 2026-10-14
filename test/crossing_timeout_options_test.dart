import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/guidance_speech.dart';

import 'navigation_fixtures.dart';
import 'navigation_language_test.dart' show bannedIn;

/// Madde 7: karşıya geçiş zaman aşımı seçenekleri. VARSAYILAN DEĞİŞMEDİ
/// (90 sn sonra devam); (a) süre, (b) hatırlatma kipi, (c) ışık süresi
/// arayüzü bayrakla seçilir. Hangisi varsayılan olacak: kullanıcı kararı.
class _FixedTiming extends CrossingSignalTiming {
  final Duration? value;
  const _FixedTiming(this.value);

  @override
  Duration? maxPauseFor(int? step) => value;
}

void main() {
  const toCrossing = [(0.0, 0.0), (0.0, 200.0), (150.0, 200.0)];

  ({GuidanceEngine e, int t}) paused(GuidanceConfig config) {
    final e = GuidanceEngine(testRoute(), config: config, startedAt: at(0));
    final path = walkPath(toCrossing);
    for (var i = 0; i < path.length; i++) {
      if (e.update(fixAt(path[i].$1, path[i].$2, seconds: i)).any((x) => x is CrossingPoint)) {
        return (e: e, t: i);
      }
    }
    fail('geçiş noktası hiç tetiklenmedi');
  }

  test('varsayılan eski davranış: resume, 90 sn, hatırlatma yok', () {
    const c = GuidanceConfig();
    expect(c.crossingTimeoutAction, CrossingTimeoutAction.resume);
    expect(c.crossingMaxPause, const Duration(seconds: 90));
    expect(c.crossingSignalTiming, isNull);
    final (:e, :t) = paused(c);
    expect(e.tick(at(t + 90)).first, isA<CrossingTimedOut>());
  });

  test('(a) süre uzatılır', () {
    final (:e, :t) = paused(const GuidanceConfig(crossingMaxPause: Duration(seconds: 180)));
    expect(e.tick(at(t + 179)), isEmpty);
    expect(e.tick(at(t + 180)).first, isA<CrossingTimedOut>());
  });

  test('(b) hatırlatma: devam etmez, N kez hatırlatır, sonra devam', () {
    final (:e, :t) = paused(const GuidanceConfig(
      crossingTimeoutAction: CrossingTimeoutAction.remind,
      crossingMaxReminders: 2,
    ));
    expect(e.tick(at(t + 90)), [isA<CrossingReminder>()]);
    expect(e.isPausedForCrossing, isTrue, reason: 'hatırlatma navigasyonu sürdürmez');
    expect(e.tick(at(t + 150)), isEmpty, reason: 'süre hatırlatmayla yeniden başladı');
    expect(e.tick(at(t + 180)), [isA<CrossingReminder>()]);
    expect(e.tick(at(t + 270)).first, isA<CrossingTimedOut>());
    expect(e.isPausedForCrossing, isFalse);
  });

  test('(b) hatırlatma kipinde de "geçtim"/çift dokunuş ve konum çıkışı çalışır', () {
    final (:e, :t) = paused(const GuidanceConfig(crossingTimeoutAction: CrossingTimeoutAction.remind));
    e.tick(at(t + 90));
    expect(e.resumeFromCrossing().first, isA<CrossingResumed>());
    expect(e.isPausedForCrossing, isFalse);
  });

  test('(b) yeni geçişte hatırlatma sayacı sıfırdan başlar', () {
    final e = GuidanceEngine(testRoute(),
        config: const GuidanceConfig(
          crossingTimeoutAction: CrossingTimeoutAction.remind,
          crossingMaxReminders: 1,
        ),
        startedAt: at(0));
    e.pauseForCrossing(at(0));
    expect(e.tick(at(90)), [isA<CrossingReminder>()]);
    expect(e.tick(at(180)).first, isA<CrossingTimedOut>());
    e.pauseForCrossing(at(200));
    expect(e.tick(at(290)), [isA<CrossingReminder>()]);
  });

  test('(c) ışık süresi arayüzü: değer verirse o, null ise sabit süre', () {
    final withData = paused(const GuidanceConfig(crossingSignalTiming: _FixedTiming(Duration(seconds: 40))));
    expect(withData.e.tick(at(withData.t + 40)).first, isA<CrossingTimedOut>());
    final noData = paused(const GuidanceConfig(crossingSignalTiming: _FixedTiming(null)));
    expect(noData.e.tick(at(noData.t + 89)), isEmpty);
    expect(noData.e.tick(at(noData.t + 90)).first, isA<CrossingTimedOut>());
  });

  test('hatırlatma cümlesi bilgi kipinde, yasaklı kelime yok, güvenlik kararı vermez', () {
    final text = describeEvent(const CrossingReminder());
    expect(bannedIn(text), isEmpty, reason: text);
    for (final w in ['yeşil', 'kırmızı', 'araç', 'güvenli']) {
      expect(text.toLowerCase(), isNot(contains(w)));
    }
  });
}
