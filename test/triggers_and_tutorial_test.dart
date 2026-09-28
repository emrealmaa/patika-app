import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'test_harness.dart';

void main() {
  const listenDelay = Duration(milliseconds: 500);

  group('gözlük tetikleyicileri', () {
    test('tek dokunuş dinlemeyi başlatır', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue);
        expect(h.app.voice.source, ListenSource.glasses);
        h.dispose();
      });
    });

    test('çift dokunuş son duyuruyu tekrarlar', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.submitVoiceCommand(BleCommand.fromWire('SAAT', null));
        h.speakAll(async);
        final last = h.tts.spoken.last;

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        h.speakAll(async);
        expect(h.tts.spoken.last, last);
        expect(h.tts.spoken.where((t) => t == last), hasLength(2));
        h.dispose();
      });
    });

    test('çift dokunuş: tekrar edilecek bir şey yoksa bunu söyler', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        h.speakAll(async);
        expect(h.tts.spoken, ['Tekrar edilecek bir şey yok']);
        h.dispose();
      });
    });

    test('uzun basış SOS için ayrılmış (henüz hazır değil, yüksek öncelik)', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.feedback.say('Sıradan bir sonuç');
        async.flushMicrotasks();
        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.flushMicrotasks();
        expect(h.tts.stops, 1, reason: 'yüksek öncelik sıradan duyuruyu keser');
        expect(h.tts.spoken.last, contains('Bu sürümde acil durum mesajı gönderilemiyor'));
        h.dispose();
      });
    });

    test('çift baş sallama: ayar kapalıyken yok sayılır, açıkken dinler', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectGesture(GlassesGesture.doubleNod);
        async.elapse(listenDelay);
        expect(h.speech.initCalls, 0);

        h.settings.update(const Settings(nodToListen: true));
        async.flushMicrotasks();
        h.app.simulator!.injectGesture(GlassesGesture.doubleNod);
        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue);
        expect(h.app.voice.source, ListenSource.gesture);
        h.dispose();
      });
    });
  });

  group('gelen arama simülasyonu (Faz 4b)', () {
    test('çalmaya başlayınca yüksek öncelikle "X arıyor" duyurulur', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.feedback.say('Sıradan bir sonuç');
        async.flushMicrotasks();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        async.flushMicrotasks();
        expect(h.tts.stops, 1, reason: 'yüksek öncelik sıradan duyuruyu keser');
        expect(h.tts.spoken.last, 'Ahmet Yılmaz arıyor');
        expect(h.app.ringingCall?.callerName, 'Ahmet Yılmaz');
        h.dispose();
      });
    });

    test('çalarken tek dokunuş dinlemeyi başlatmaz, aramayı açar', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);

        expect(h.speech.listening, isFalse,
            reason: 'çalarken tek dokunuş dinlemeye gitmemeli');
        expect(h.tts.spoken.last, 'Ahmet Yılmaz ile görüşme açılıyor');
        expect(h.app.ringingCall, isNull, reason: 'açınca çalma bitmeli');
        h.dispose();
      });
    });

    test('çalarken uzun basış SOS değil, aramayı reddeder', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.flushMicrotasks();

        expect(h.tts.spoken.last, 'Ahmet Yılmaz için gelen arama reddedildi');
        expect(h.tts.spoken, isNot(contains('Bu sürümde acil durum mesajı gönderilemiyor')));
        expect(h.app.ringingCall, isNull);
        h.dispose();
      });
    });

    test('arama bitince uzun basış yine SOS yer tutucusuna döner', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.longPress);
        h.speakAll(async);

        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.flushMicrotasks();
        expect(h.tts.spoken.last, contains('Bu sürümde acil durum mesajı gönderilemiyor'));
        h.dispose();
      });
    });
  });

  group('sesli eğitim', () {
    test('tüm adımlar sırayla okunur, sonunda bitti denir ve kaydedilir', () {
      fakeAsync((async) {
        final h = Harness()..tutorialProgress.done = false;
        h.app.tutorial.startIfFirstRun();
        for (var i = 0; i < 20; i++) {
          h.speakAll(async);
          async.elapse(const Duration(seconds: 1));
        }
        final steps = h.app.tutorial.steps;
        expect(h.tts.spoken.take(steps.length), steps);
        expect(h.tts.spoken.last, startsWith('Eğitim bitti'));
        expect(h.tutorialProgress.done, isTrue);
        h.dispose();
      });
    });

    test('daha önce dinlendiyse açılışta başlamaz', () {
      fakeAsync((async) {
        final h = Harness(); // tutorialProgress.done = true
        h.app.tutorial.startIfFirstRun();
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty);
        h.dispose();
      });
    });

    test('yüksek öncelikli duyuruyla kesilen adım tekrar okunur', () {
      fakeAsync((async) {
        final h = Harness()..tutorialProgress.done = false;
        h.app.tutorial.start();
        async.flushMicrotasks();
        final first = h.app.tutorial.steps.first;
        expect(h.tts.spoken, [first]);

        // Adım okunurken "Gözlük bağlandı" araya girer.
        h.app.feedback.say('Gözlük bağlandı', priority: AnnouncementPriority.high);
        async.flushMicrotasks();
        h.speakAll(async);
        async.elapse(const Duration(seconds: 1));
        h.speakAll(async);

        expect(h.tts.spoken.take(3), [first, 'Gözlük bağlandı', first]);
        h.dispose();
      });
    });

    test('dinleme başlarsa eğitim durur ve "dinlendi" sayılır', () {
      fakeAsync((async) {
        final h = Harness()..tutorialProgress.done = false;
        h.app.tutorial.start();
        async.flushMicrotasks();
        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);
        h.speakAll(async);
        async.elapse(const Duration(seconds: 5));
        h.speakAll(async);

        expect(h.app.tutorial.running, isFalse);
        expect(h.tts.spoken, [h.app.tutorial.steps.first],
            reason: 'durdurulan eğitim bir sonraki adıma geçmez');
        expect(h.tutorialProgress.done, isTrue);
        h.dispose();
      });
    });

    test('"eğitimi başlat" komutu eğitimi yeniden başlatır', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('eğitimi başlat');
        async.flushMicrotasks();
        expect(h.app.tutorial.running, isTrue);
        expect(h.tts.spoken.first, h.app.tutorial.steps.first);
        h.dispose();
      });
    });
  });
}
