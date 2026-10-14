import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';

import 'test_harness.dart';

/// Madde 9 kilidi (bkz. docs/barge_in_tasarim.md): sesle araya girme YOK.
/// TTS konuşurken mikrofon açılmaz; kesme yalnızca tetikleyiciyle olur ve
/// tetikleyici önce TTS'i susturur. Barge-in yazılırsa bu test bayrak KAPALI
/// durum için aynen geçmeye devam etmeli.
void main() {
  const listenDelay = Duration(milliseconds: 500);

  test('uzun bir duyuru sürerken mikrofon kendiliğinden açılmaz', () {
    fakeAsync((async) {
      final h = Harness();
      h.app.feedback.say('Uzun bir bilgi duyurusu sürüyor');
      for (var i = 0; i < 10; i++) {
        async.elapse(const Duration(seconds: 1));
        expect(h.speech.listening, isFalse);
      }
      h.dispose();
    });
  });

  test('tetikleyici (gözlük dokunuşu) önce TTS\'i susturur, sonra dinler', () {
    fakeAsync((async) {
      final h = Harness();
      h.app.feedback.say('Uzun bir bilgi duyurusu sürüyor');
      async.flushMicrotasks();
      final stopsBefore = h.tts.stops;
      h.app.simulator!.injectButton(GlassesButton.tap);
      async.elapse(listenDelay);
      expect(h.tts.stops, greaterThan(stopsBefore));
      expect(h.speech.listening, isTrue);
      h.dispose();
    });
  });
}
