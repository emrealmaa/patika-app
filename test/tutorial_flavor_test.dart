import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/l10n/strings_tr.dart';

import 'fakes.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// Madde 5 (TODO 17): eğitimin SOS cümlesi derleme türüne göre. `direct`te
/// mesaj gönderilir denir; `play`de (iOS dahil) gönderilemediği söylenir.
/// İkisinde de "Patika acil durum servisi değildir." korunur.
void main() {
  List<String> played(Harness h, FakeAsync async) {
    h.tutorialProgress.done = false;
    h.app.tutorial.startIfFirstRun();
    for (var i = 0; i < 20; i++) {
      h.speakAll(async);
      async.elapse(const Duration(seconds: 1));
    }
    return h.tts.spoken;
  }

  test('direct: "acil kişilerinize mesaj gönderilir"', () {
    fakeAsync((async) {
      final h = Harness(direct: FakeDirectActions());
      final spoken = played(h, async);
      expect(spoken.take(Tr.tutorialSteps.length), Tr.tutorialSteps);
      expect(spoken.join(' '), contains('acil kişilerinize mesaj gönderilir'));
      h.dispose();
    });
  });

  test('play: gönderilemediği söylenir, "gönderilir" denmez', () {
    fakeAsync((async) {
      final h = Harness();
      final spoken = played(h, async).join(' ');
      expect(spoken, contains(Tr.tutorialSosPlay));
      expect(spoken, isNot(contains('mesaj gönderilir')));
      h.dispose();
    });
  });

  test('iki türde de "Patika acil durum servisi değildir." ve aynı adım sayısı', () {
    for (final direct in [true, false]) {
      final steps = Tr.tutorialStepsFor(direct: direct);
      expect(steps.join(' '), contains('Patika acil durum servisi değildir.'));
      expect(steps.length, Tr.tutorialSteps.length);
      expect(steps.take(steps.length - 1), Tr.tutorialSteps.take(steps.length - 1));
    }
  });

  test('play SOS cümlesi bilgi kipinde, yasaklı kelime yok', () {
    expect(bannedIn(Tr.tutorialSosPlay), isEmpty);
    expect(Tr.tutorialSosPlay, isNot(contains('arayın')));
  });
}
