import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'test_harness.dart';

void main() {
  const listenDelay = Duration(milliseconds: 500); // earconGap + pay

  group('dinleme akışı', () {
    test('varsayılan: "Dinliyorum" yerine kısa ses, sonra mikrofon açılır', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(silenceTimeoutSeconds: 5));
        h.app.voice.startListening(ListenSource.screen);
        async.flushMicrotasks();

        expect(h.earcons.played, [Earcon.listenStart]);
        expect(h.haptics.played.map((p) => p.$1), [HapticPatternId.listening]);
        expect(h.tts.spoken, isEmpty, reason: 'earconOnly varsayılanı');
        expect(h.speech.listening, isFalse, reason: 'kısa ses bitmeden mikrofon açılmaz');

        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue);
        expect(h.speech.lastSilenceTimeout, const Duration(seconds: 5),
            reason: 'sessizlik süresi ayardan');
        expect(h.app.voice.phase, VoicePhase.listening);
        h.dispose();
      });
    });

    test('sesli bildirim modunda "Dinliyorum" söylenir', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(feedbackMode: FeedbackMode.speech));
        h.app.voice.startListening(ListenSource.screen);
        async.flushMicrotasks();
        expect(h.tts.spoken, ['Dinliyorum']);
        async.elapse(const Duration(seconds: 2));
        expect(h.speech.listening, isTrue);
        h.dispose();
      });
    });

    test('normal komut: "Şunu anladım" -> komut işlenir -> sonuç okunur', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);

        h.speech.say('saat kaç');
        async.flushMicrotasks();
        expect(h.tts.spoken, ['Şunu anladım: saat kaç']);
        expect(h.app.voice.phase, VoicePhase.processing);

        async.elapse(VoiceController.confirmGap);
        h.speakAll(async);
        expect(h.tts.spoken.last, startsWith('Saat '));
        expect(h.app.log.first.intent, PatikaIntent.saat);
        expect(h.app.voice.phase, VoicePhase.idle);
        expect(h.app.voice.lastHeard, 'saat kaç');
        h.dispose();
      });
    });

    test('dinlerken tekrar tetiklenirse iptal eder (aç/kapat)', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.app.voice.startListening(ListenSource.glasses);
        async.flushMicrotasks();

        expect(h.speech.cancelCalls, 1);
        expect(h.app.voice.phase, VoicePhase.idle);
        expect(h.earcons.played.last, Earcon.listenEnd);
        h.dispose();
      });
    });

    test('tetikleyiciyle araya girme: dinleme başlarken süren konuşma susar', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.feedback.say('Çok uzun bir komut sonucu okunuyor');
        async.flushMicrotasks();
        expect(h.tts.spoken, hasLength(1));

        h.app.voice.startListening(ListenSource.glasses);
        async.flushMicrotasks();
        expect(h.tts.stops, 1);
        h.dispose();
      });
    });

    test('mikrofon izni yoksa sebebi söylenir, tanıyıcı açılmaz', () {
      fakeAsync((async) {
        final h = Harness()..micGranted = false;
        h.app.voice.startListening(ListenSource.screen);
        async.flushMicrotasks();

        expect(h.speech.initCalls, 0);
        expect(h.tts.spoken, ['Mikrofon izni verilmedi']);
        expect(h.app.voice.phase, VoicePhase.idle);
        h.dispose();
      });
    });

    test('tanıma hatası: "anlaşılamadı" titreşimiyle mesaj okunur', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.fail('Sizi duyamadım, tekrar deneyin');
        async.flushMicrotasks();

        expect(h.tts.spoken, ['Sizi duyamadım, tekrar deneyin']);
        expect(h.haptics.played.last.$1, HapticPatternId.notUnderstood);
        expect(h.app.voice.phase, VoicePhase.idle);
        h.dispose();
      });
    });

    test('komut işlenirken gelen tetiklemeler yok sayılır', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('saat kaç');
        async.flushMicrotasks();

        h.app.voice.startListening(ListenSource.glasses);
        async.flushMicrotasks();
        expect(h.speech.initCalls, 1);
        expect(h.app.voice.phase, VoicePhase.processing);
        h.dispose();
      });
    });
  });

  group('evrensel komutlar', () {
    test('"tekrar et" teyitsiz uygulanır ve "Dinliyorum"u değil son sonucu tekrarlar', () {
      fakeAsync((async) {
        // Sesli bildirim modu: "Dinliyorum" gerçekten okunuyor ama
        // tekrarlanacak son duyuru sayılmamalı.
        final h = Harness(initial: const Settings(feedbackMode: FeedbackMode.speech));
        h.app.submitVoiceCommand(BleCommand.fromWire('SAAT', null));
        h.speakAll(async);
        final timeResult = h.tts.spoken.last;

        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(seconds: 2));
        h.speakAll(async);
        h.speech.say('tekrar et');
        h.speakAll(async);

        expect(h.tts.spoken, isNot(contains('Şunu anladım: tekrar et')));
        expect(h.tts.spoken.last, timeResult);
        h.dispose();
      });
    });

    test('"dur" konuşmayı keser ve kendisi hiçbir şey söylemez', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('dur');
        h.speakAll(async);

        expect(h.tts.spoken, isEmpty);
        expect(h.app.log.first.intent, PatikaIntent.dur);
        expect(h.haptics.played.last.$1, HapticPatternId.understood);
        h.dispose();
      });
    });

    test('"ne yapabilirim" komut listesini okur', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(verbosity: Verbosity.short));
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('ne yapabilirim');
        h.speakAll(async);

        expect(h.tts.spoken.single, startsWith('Şunları söyleyebilirsiniz'));
        h.dispose();
      });
    });

    test('"yardım" SOS\'a gider (Faz 7\'ye kadar hazır değil der)', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('yardım edin');
        h.speakAll(async);

        expect(h.app.log.first.intent, PatikaIntent.sos);
        expect(h.tts.spoken.single, contains('Acil durum özelliği henüz hazır değil'));
        h.dispose();
      });
    });
  });

  test('mikrofon izni ilk alındığında geri çağırma bir kez tetiklenir', () {
    fakeAsync((async) {
      final h = Harness();
      var granted = 0;
      final voice = VoiceController(
        speech: h.speech,
        feedback: h.app.feedback,
        ensureMicPermission: () async => true,
        submit: (_) async {},
        onMicrophoneGranted: () => granted++,
      );
      voice.startListening(ListenSource.screen);
      async.elapse(listenDelay);
      voice.startListening(ListenSource.screen); // iptal
      async.flushMicrotasks();
      voice.startListening(ListenSource.screen);
      async.elapse(listenDelay);
      expect(granted, 1);
      voice.dispose();
      h.dispose();
    });
  });
}
