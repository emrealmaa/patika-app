import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';

import 'navigation_fixtures.dart';
import 'test_harness.dart';

void main() {
  const listenDelay = Duration(milliseconds: 500);

  void expectIntent(String text, PatikaIntent intent) {
    final cmd = classifyVoiceCommand(text);
    expect(cmd.intent, intent, reason: '"$text" niyeti');
    expect(cmd.entity, isNull, reason: '"$text" entity');
  }

  group('sınıflandırıcı: navigasyon kontrolü', () {
    test('"geçtim" ve varyantları GECTIM (GECIS_MODU\'na kaymaz)', () {
      for (final text in [
        'geçtim',
        'Geçtim.',
        'karşıya geçtim',
        'tamam geçtim',
        'geçtim tamam',
        'lütfen geçtim',
        'karşıdayım',
        'karşıya ulaştım',
        'geçtik',
      ]) {
        expectIntent(text, PatikaIntent.gectim);
      }
    });

    test('"karşıya geçmek istiyorum" hâlâ GECIS_MODU', () {
      expect(classifyVoiceCommand('karşıya geçmek istiyorum').intent, PatikaIntent.gecisModu);
      expect(classifyVoiceCommand('karşıya geçtim ama yol uzun').intent, isNot(PatikaIntent.gectim),
          reason: 'yalnızca tüm cümle "geçtim" ise (yanlışlıkla devam ettirmesin)');
    });

    test('navigasyonu bitir', () {
      for (final text in [
        'navigasyonu bitir',
        'navigasyonu kapat',
        'navigasyonu durdur',
        'yönlendirmeyi kapat',
        'rotayı iptal et',
        'gitmekten vazgeç',
      ]) {
        expectIntent(text, PatikaIntent.navigasyonBitir);
      }
    });

    test('"durdur" tek başına DUR: konuşmayı keser, navigasyonu kapatmaz', () {
      expectIntent('durdur', PatikaIntent.dur);
      expectIntent('iptal et', PatikaIntent.dur);
    });

    test('ne kadar kaldı', () {
      for (final text in [
        'ne kadar kaldı',
        'Ne kadar kaldı?',
        'kaç dakika kaldı',
        'kaç metre kaldı',
        'hedefe ne kadar var',
        'ne zaman varırım',
      ]) {
        expectIntent(text, PatikaIntent.navigasyonKalan);
      }
    });

    test('komşu niyetler bozulmadı', () {
      expectIntent('saat kaç', PatikaIntent.saat);
      expect(classifyVoiceCommand('Kadıköy İskelesine götür').intent, PatikaIntent.navigasyon);
      expect(classifyVoiceCommand("Ahmet'i ara").intent, PatikaIntent.ara);
    });

    test('wire adları', () {
      expect(PatikaIntent.fromWireName('NAV_BITIR'), PatikaIntent.navigasyonBitir);
      expect(PatikaIntent.fromWireName('NAV_KALAN'), PatikaIntent.navigasyonKalan);
      expect(PatikaIntent.fromWireName('GECTIM'), PatikaIntent.gectim);
    });
  });

  group('komutlar navigasyona işliyor', () {
    /// Navigasyonu başlatıp konuşmayı akıtır.
    void startNav(Harness h, FakeAsync async) {
      h.app.navigation.start(testRoute());
      async.flushMicrotasks();
    }

    void walkToCrossing(Harness h, FakeAsync async) {
      for (final (x, y) in walkPath([(0, 0), (0, 200), (140, 200)])) {
        h.location.emit(enu(x, y));
        async.elapse(const Duration(seconds: 1));
        h.speakAll(async);
      }
    }

    test('navigasyon yokken üçü de "çalışan bir navigasyon yok" der', () {
      fakeAsync((async) {
        final h = Harness();
        for (final wire in ['GECTIM', 'NAV_KALAN', 'NAV_BITIR']) {
          h.app.submitVoiceCommand(BleCommand.fromWire(wire, null));
          async.flushMicrotasks();
        }
        h.speakAll(async);
        expect(h.tts.spoken, everyElement('Şu an çalışan bir navigasyon yok'));
        h.dispose();
      });
    });

    test('"ne kadar kaldı" kalan mesafe ve süreyi okur', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        h.app.submitVoiceCommand(BleCommand.fromWire('NAV_KALAN', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Hedefe 450 metre, yaklaşık 6 dakika kaldı');
        h.dispose();
      });
    });

    test('"navigasyonu bitir" kapatır: konum kaynağı durur', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        expect(h.location.isRunning, isTrue);

        h.app.submitVoiceCommand(BleCommand.fromWire('NAV_BITIR', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Navigasyon kapatıldı');
        expect(h.app.navigation.active, isFalse);
        expect(h.location.isRunning, isFalse);
        h.dispose();
      });
    });

    test('"geçtim" duraklamayı bitirir; devam cümlesi bir kez okunur', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        walkToCrossing(h, async);
        expect(h.app.navigation.isPausedForCrossing, isTrue);

        h.app.submitVoiceCommand(BleCommand.fromWire('GECTIM', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.app.navigation.isPausedForCrossing, isFalse);
        expect(h.tts.spoken.where((s) => s == 'Navigasyon devam ediyor'), hasLength(1));
        h.dispose();
      });
    });

    test('duraklama yokken "geçtim": "duraklatılmış navigasyon yok"', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        h.app.submitVoiceCommand(BleCommand.fromWire('GECTIM', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Duraklatılmış bir navigasyon yok');
        h.dispose();
      });
    });

    test('GECIS_MODU: navigasyon varsa duraklatılır ve söylenir; yoksa eski cevap', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.submitVoiceCommand(BleCommand.fromWire('GECIS_MODU', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Karşıya geçiş modu henüz hazır değil');

        startNav(h, async);
        h.app.submitVoiceCommand(BleCommand.fromWire('GECIS_MODU', null));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, startsWith('Karşıya geçiş modu henüz hazır değil. Navigasyon duraklatıldı'));
        expect(h.app.navigation.isPausedForCrossing, isTrue);
        h.dispose();
      });
    });
  });

  group('gözlük butonu karşıya geçiş duraklamasında', () {
    /// Navigasyonu başlatıp geçiş noktasında duraklatır.
    Harness pausedHarness(FakeAsync async) {
      final h = Harness();
      h.app.navigation.start(testRoute());
      async.flushMicrotasks();
      for (final (x, y) in walkPath([(0, 0), (0, 200), (140, 200)])) {
        h.location.emit(enu(x, y));
        async.elapse(const Duration(seconds: 1));
        h.speakAll(async);
      }
      expect(h.app.navigation.isPausedForCrossing, isTrue);
      return h;
    }

    test('ÇİFT dokunuş duraklamayı bitirir; "son duyuruyu tekrarla" yerine geçer', () {
      fakeAsync((async) {
        final h = pausedHarness(async);
        final before = h.tts.spoken.length;

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.app.navigation.isPausedForCrossing, isFalse);
        expect(h.tts.spoken.sublist(before), contains('Navigasyon devam ediyor'));
        expect(h.speech.listening, isFalse);
        h.dispose();
      });
    });

    test('duraklama yokken çift dokunuş her zamanki gibi son duyuruyu tekrarlar', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.submitVoiceCommand(BleCommand.fromWire('SAAT', null));
        async.flushMicrotasks();
        h.speakAll(async);
        final first = h.tts.spoken.last;

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, first);
        expect(h.tts.spoken.where((s) => s == first), hasLength(2));
        h.dispose();
      });
    });

    test('TEK dokunuş duraklamada da dinletir ve duraklamayı bitirmez', () {
      fakeAsync((async) {
        final h = pausedHarness(async);

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);

        expect(h.speech.listening, isTrue);
        expect(h.app.navigation.isPausedForCrossing, isTrue);
        h.dispose();
      });
    });

    test('duraklama yokken tek dokunuş her zamanki gibi dinletir (navigasyon açıkken de)', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.navigation.start(testRoute());
        async.flushMicrotasks();

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue);
        h.dispose();
      });
    });

    test('duraklamadayken "yardım" SOS yoluna gider (kavşakta güvenlik komutu erişilebilir)', () {
      fakeAsync((async) {
        final h = pausedHarness(async);

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);
        h.speech.say('yardım');
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.app.log.first.intent, PatikaIntent.sos);
        expect(h.tts.spoken.last, startsWith('Bu sürümde acil durum mesajı gönderilemiyor'));
        // SOS, navigasyonun duraklama durumunu kendiliğinden değiştirmez.
        expect(h.app.navigation.isPausedForCrossing, isTrue);
        h.dispose();
      });
    });

    test('duraklamadayken "geçtim" (sesle) duraklamayı bitirir', () {
      fakeAsync((async) {
        final h = pausedHarness(async);

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.elapse(listenDelay);
        h.speech.say('geçtim');
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.app.navigation.isPausedForCrossing, isFalse);
        h.dispose();
      });
    });

    test('duraklamadayken uzun basış da SOS yer tutucusuna gider', () {
      fakeAsync((async) {
        final h = pausedHarness(async);

        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.tts.spoken.last, startsWith('Bu sürümde acil durum mesajı gönderilemiyor'));
        expect(h.app.navigation.isPausedForCrossing, isTrue);
        h.dispose();
      });
    });

    test('sınıflandırıcı: "yardım", "imdat", "acil durum" duraklamadan bağımsız SOS', () {
      for (final text in ['yardım', 'imdat', 'acil durum', 'lütfen yardım']) {
        expect(classifyVoiceCommand(text).intent, PatikaIntent.sos, reason: text);
      }
    });
  });

  group('konum izni: eğitim sonunda (melez akışın ilk kanalı)', () {
    void runTutorial(Harness h, FakeAsync async) {
      for (var i = 0; i < 20; i++) {
        h.speakAll(async);
        async.elapse(const Duration(seconds: 1));
      }
    }

    test('ilk açılış eğitimi bitince izin yoksa sesli açıklamayla istenir', () {
      fakeAsync((async) {
        final h = Harness()
          ..tutorialProgress.done = false
          ..locationAccess.granted = false;
        h.app.tutorial.startIfFirstRun();
        runTutorial(h, async);
        expect(h.locationAccess.requests, 1);
        h.dispose();
      });
    });

    test('izin zaten varsa sormaz', () {
      fakeAsync((async) {
        final h = Harness()..tutorialProgress.done = false;
        h.app.tutorial.startIfFirstRun();
        runTutorial(h, async);
        expect(h.locationAccess.requests, 0);
        h.dispose();
      });
    });

    test('eğitim yeniden dinlenirken ("eğitimi başlat") tekrar sormaz', () {
      fakeAsync((async) {
        final h = Harness()..locationAccess.granted = false;
        h.app.tutorial.start();
        runTutorial(h, async);
        expect(h.locationAccess.requests, 0);
        h.dispose();
      });
    });

    test('kullanıcı eğitimi durdurduysa sormaz (ilk navigasyondaki yedek devreye girer)', () {
      fakeAsync((async) {
        final h = Harness()
          ..tutorialProgress.done = false
          ..locationAccess.granted = false;
        h.app.tutorial.startIfFirstRun();
        async.flushMicrotasks();
        h.app.simulator!.injectButton(GlassesButton.tap); // dinlemek eğitimi durdurur
        async.elapse(listenDelay);
        runTutorial(h, async);
        expect(h.locationAccess.requests, 0);
        h.dispose();
      });
    });
  });
}
