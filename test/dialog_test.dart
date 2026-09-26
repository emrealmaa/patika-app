import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/l10n/turkish_suffix.dart';
import 'package:patika_app/voice/reply_parser.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'test_harness.dart';

void main() {
  const listenDelay = Duration(milliseconds: 500);

  /// Komutu tetikleyiciyle verir (Konuş butonu).
  void command(Harness h, FakeAsync async, String text) {
    h.app.voice.startListening(ListenSource.screen);
    async.elapse(listenDelay);
    h.speech.say(text);
    async.flushMicrotasks();
  }

  /// Sorunun bitmesini bekler, dinlemenin TETİKLEYİCİSİZ açıldığını doğrular
  /// ve cevabı verir.
  void answer(Harness h, FakeAsync async, String text) {
    h.speakAll(async);
    async.elapse(listenDelay);
    expect(h.speech.listening, isTrue, reason: 'soru bitince dinleme açılmalı ("$text" öncesi)');
    h.speech.say(text);
    async.flushMicrotasks();
  }

  group('MESAJ akışı', () {
    test('tarifteki örnek: Kime -> Ayşe -> Ne yazayım -> dikte -> geri okuma -> evet', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'mesaj gönder');
        expect(h.tts.spoken, [Tr.dialogWhoToMessage]);

        answer(h, async, 'Ayşe');
        expect(h.tts.spoken.last, Tr.dialogWhatToWrite);

        h.speakAll(async);
        async.elapse(listenDelay);
        expect(h.speech.lastDictation, isTrue, reason: 'mesaj metni dikte modunda dinlenir');
        expect(h.speech.lastSilenceTimeout, const Duration(seconds: 5), reason: '3 sn + 2 sn');
        h.speech.say('Beş dakikaya oradayım');
        async.flushMicrotasks();
        expect(h.tts.spoken.last, "Ayşe Demir'e şu mesaj: Beş dakikaya oradayım. Göndereyim mi?");

        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.opened.single.toString(),
            'sms:05347778899?body=${Uri.encodeComponent('Beş dakikaya oradayım')}');
        expect(h.tts.spoken.last, startsWith('Ayşe Demir için mesaj hazır'));
        expect(h.app.log.first.intent, PatikaIntent.mesaj);
        expect(h.app.log.first.entity, 'Ayşe Demir');
        expect(h.app.dialogs.active, isFalse);
        h.dispose();
      });
    });

    test('"düzelt" metni yeniden aldırır, "tekrar oku" yeniden okur', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'annemle mesajlaş');
        answer(h, async, 'geliyorum');
        final review = h.tts.spoken.last;

        answer(h, async, 'tekrar oku');
        expect(h.tts.spoken.last, review);

        answer(h, async, 'düzelt');
        expect(h.tts.spoken.last, Tr.dialogWhatToWrite);
        answer(h, async, 'biraz geç kalacağım');
        answer(h, async, 'gönder');
        h.speakAll(async);
        expect(Uri.decodeComponent(h.opened.single.toString()), endsWith('body=biraz geç kalacağım'));
        h.dispose();
      });
    });
  });

  group('ARA akışı', () {
    test('iki Ahmet: sıra sayısıyla seçim -> onay -> arama', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ahmet'i ara");
        expect(h.tts.spoken.single,
            'İki kişi buldum: birinci Ahmet Yılmaz, ikinci Ahmet Kaya. Hangisi?');

        answer(h, async, 'ikinci');
        expect(h.tts.spoken.last, "Ahmet Kaya'yı arayayım mı?");

        answer(h, async, 'evet ara');
        h.speakAll(async);
        expect(h.opened.single.toString(), 'tel:05334445566');
        expect(h.app.log.first.entity, 'Ahmet Kaya');
        h.dispose();
      });
    });

    test('iki Ahmet: soyadıyla seçim', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ahmet'i ara");
        answer(h, async, 'Yılmaz olan');
        expect(h.tts.spoken.last, "Ahmet Yılmaz'ı arayayım mı?");
        h.dispose();
      });
    });

    test('"Ara" tek başına: Kimi arayayım -> Annem', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'ara');
        expect(h.tts.spoken.single, Tr.dialogWhoToCall);
        answer(h, async, 'annemi');
        expect(h.tts.spoken.last, "Annem'i arayayım mı?");
        h.dispose();
      });
    });

    test('"hayır" iptal eder, hiçbir şey aranmaz', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ayşe'yi ara");
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(h.opened, isEmpty);
        expect(h.tts.spoken.last, Tr.dialogCancelled);
        expect(h.app.log.first.result.success, isFalse);
        h.dispose();
      });
    });

    test('bulunamayan kişi bir kez daha sorulur', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Zeynep'i ara");
        expect(h.tts.spoken.single, "Zeynep'i rehberde bulamadım. Kimi arayayım?");
        answer(h, async, 'Ayşe');
        expect(h.tts.spoken.last, "Ayşe Demir'i arayayım mı?");
        h.dispose();
      });
    });

    test('anlaşılmayan onay bir kez ipucuyla sorulur, ikincide iptal', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ayşe'yi ara");
        answer(h, async, 'bilmiyorum');
        expect(h.tts.spoken.last, "${Tr.dialogYesNoHint} Ayşe Demir'i arayayım mı?");
        answer(h, async, 'belki');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.dialogNotUnderstood);
        expect(h.opened, isEmpty);
        h.dispose();
      });
    });
  });

  group('her adımda geçerli olanlar', () {
    test('"dur" diyaloğu iptal eder', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'mesaj gönder');
        answer(h, async, 'dur');
        h.speakAll(async);
        expect(h.app.dialogs.active, isFalse);
        expect(h.tts.spoken.last, Tr.dialogCancelled);
        h.dispose();
      });
    });

    test('"tekrar et" son soruyu tekrarlar', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ahmet'i ara");
        final question = h.tts.spoken.single;
        answer(h, async, 'tekrar et');
        expect(h.tts.spoken.where((t) => t == question), hasLength(2),
            reason: 'soru gerçekten tekrar okunmalı (birleştirme kuralına takılmadan)');
        h.speakAll(async);
        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue, reason: 'tekrardan sonra dinleme yeniden açılmalı');
        expect(h.app.dialogs.active, isTrue);
        h.dispose();
      });
    });

    test('SOS diyaloğu keser ve işlenir (güvenlik önce)', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'mesaj gönder');
        answer(h, async, 'imdat');
        h.speakAll(async);
        expect(h.app.dialogs.active, isFalse);
        expect(h.app.log.first.intent, PatikaIntent.sos);
        h.dispose();
      });
    });

    test('cevap gelmezse soru bir kez tekrarlanır, ikincide iptal', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'ara');
        h.speakAll(async);
        async.elapse(listenDelay);
        h.speech.fail(Tr.didNotHear);
        async.flushMicrotasks();
        expect(h.tts.spoken.last, '${Tr.dialogDidNotHear} ${Tr.dialogWhoToCall}');

        h.speakAll(async);
        async.elapse(listenDelay);
        h.speech.fail(Tr.didNotHear);
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.dialogTimedOut);
        expect(h.app.dialogs.active, isFalse);
        h.dispose();
      });
    });

    test('dinlerken dokunmak diyaloğu iptal eder', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'ara');
        h.speakAll(async);
        async.elapse(listenDelay);
        expect(h.speech.listening, isTrue);

        h.app.voice.startListening(ListenSource.glasses);
        h.speakAll(async);
        expect(h.app.dialogs.active, isFalse);
        expect(h.tts.spoken.last, Tr.dialogCancelled);
        h.dispose();
      });
    });

    test('soru okunurken dokunmak = şimdi cevap veriyorum', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'ara');
        expect(h.tts.spoken.single, Tr.dialogWhoToCall);

        // Soru daha bitmeden gözlüğe dokunuş: soru susar, dinleme açılır.
        h.app.voice.startListening(ListenSource.glasses);
        async.elapse(listenDelay);
        expect(h.tts.stops, 1);
        expect(h.speech.listening, isTrue);
        h.speech.say("Ayşe'yi");
        async.flushMicrotasks();
        expect(h.tts.spoken.last, "Ayşe Demir'i arayayım mı?");
        expect(h.app.dialogs.active, isTrue);
        h.dispose();
      });
    });
  });

  group('Türkçe ek', () {
    test('belirtme', () {
      expect(accusative('Ahmet Kaya'), "Ahmet Kaya'yı");
      expect(accusative('Ayşe Demir'), "Ayşe Demir'i");
      expect(accusative('Mehmet Öz'), "Mehmet Öz'ü");
      expect(accusative('Umut'), "Umut'u");
      expect(accusative('Annem'), "Annem'i");
    });

    test('yönelme', () {
      expect(dative('Ahmet Kaya'), "Ahmet Kaya'ya");
      expect(dative('Ayşe'), "Ayşe'ye");
      expect(dative('Mehmet Öz'), "Mehmet Öz'e");
      expect(dative('Umut'), "Umut'a");
    });
  });

  group('cevap anlama', () {
    test('evet / hayır (olumsuz önce)', () {
      for (final t in ['evet', 'olur', 'tamam', 'evet ara', 'gönder', 'doğru']) {
        expect(parseYesNo(t), YesNo.yes, reason: t);
      }
      for (final t in ['hayır', 'yok', 'vazgeç', 'istemiyorum', 'hayır arama', 'gerek yok']) {
        expect(parseYesNo(t), YesNo.no, reason: t);
      }
      expect(parseYesNo('belki'), YesNo.unknown);
    });

    test('seçim', () {
      const two = [
        ContactEntry('1', 'Ahmet Yılmaz', ['1']),
        ContactEntry('2', 'Ahmet Kaya', ['2']),
      ];
      expect(parseChoice('birinci', two), 0);
      expect(parseChoice('ikincisi', two), 1);
      expect(parseChoice('sonuncu', two), 1);
      expect(parseChoice('Kaya', two), 1);
      expect(parseChoice('Ahmet Yılmaz', two), 0);
      expect(parseChoice('üçüncü', two), isNull, reason: 'yalnızca iki aday var');
      expect(parseChoice('bilmiyorum', two), isNull);
    });

    test('mesaj geri okuma cevabı', () {
      expect(parseReview('evet gönder'), ReviewAction.send);
      expect(parseReview('düzelt'), ReviewAction.edit);
      expect(parseReview('değiştir'), ReviewAction.edit);
      expect(parseReview('tekrar oku'), ReviewAction.reread);
      expect(parseReview('hayır'), ReviewAction.cancel);
    });
  });
}
