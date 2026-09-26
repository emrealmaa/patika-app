import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/voice/recognition_session.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'test_harness.dart';

/// Gerçek telefon oturumunda (Galaxy S24 FE, 58 kişilik rehber) bulunan
/// dört sorunun düzeltmeleri - her test logdaki durumu birebir yansıtıyor.
void main() {
  group('1) geç gelen sonuç kaybolmasın', () {
    late List<String> events;
    late RecognitionSession session;

    setUp(() {
      events = [];
      session = RecognitionSession(
        onFinal: (t) => events.add('final:$t'),
        onError: (m) => events.add('error:$m'),
        onDone: () => events.add('done'),
      );
    });

    test('logdaki sıra: "bitti" sinyali, 170 ms sonra metin -> metin teslim edilir', () {
      fakeAsync((async) {
        session.onDone();
        async.elapse(const Duration(milliseconds: 170));
        session.onResult('hava nasıl', isFinal: false);
        async.elapse(const Duration(seconds: 2));
        expect(events, ['final:hava nasıl'], reason: 'önceden "Sizi duyamadım" deniyordu');
      });
    });

    test('hiç metin gelmezse 1 sn sonra "bitti" iletilir', () {
      fakeAsync((async) {
        session.onDone();
        async.elapse(const Duration(milliseconds: 900));
        expect(events, isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect(events, ['done']);
      });
    });

    test('hata ve bitti birlikte gelirse tek sonuç (ilki)', () {
      fakeAsync((async) {
        session.onError(Tr.didNotHear);
        session.onDone();
        async.elapse(const Duration(seconds: 2));
        expect(events, ['error:${Tr.didNotHear}']);
      });
    });

    test('bekleme süresinden sonra gelen metin yok sayılır', () {
      fakeAsync((async) {
        session.onDone();
        async.elapse(const Duration(seconds: 2));
        session.onResult('çok geç', isFinal: true);
        expect(events, ['done']);
      });
    });

    test('metin önceden geldiyse "bitti"de beklemeden teslim edilir', () {
      fakeAsync((async) {
        session.onResult('saat kaç', isFinal: false);
        session.onDone();
        expect(events, ['final:saat kaç']);
      });
    });

    test('iptal edilen oturum hiçbir şey teslim etmez', () {
      fakeAsync((async) {
        session.onDone();
        session.close();
        session.onResult('merhaba', isFinal: true);
        async.elapse(const Duration(seconds: 2));
        expect(events, isEmpty);
      });
    });
  });

  group('2) diyalog cevabına daha uzun pencere', () {
    test('komut 3 sn, diyalog cevabı 4,5 sn, dikte 5 sn', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(milliseconds: 500));
        expect(h.speech.lastSilenceTimeout, const Duration(seconds: 3));

        h.speech.say("Ayşe'yi ara");
        h.speakAll(async);
        async.elapse(const Duration(milliseconds: 500));
        expect(h.speech.lastSilenceTimeout, const Duration(milliseconds: 4500),
            reason: '"arayayım mı?" cevabı');

        h.speech.say('hayır');
        h.speakAll(async);
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(milliseconds: 500));
        h.speech.say('mesaj gönder');
        h.speakAll(async);
        async.elapse(const Duration(milliseconds: 500));
        h.speech.say('Ayşe');
        h.speakAll(async);
        async.elapse(const Duration(milliseconds: 500));
        expect(h.speech.lastSilenceTimeout, const Duration(seconds: 5), reason: 'dikte');
        h.dispose();
      });
    });

    test('soru okunurken dokunarak verilen cevap da uzun pencereyle dinlenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(milliseconds: 500));
        h.speech.say("Ayşe'yi ara");
        async.flushMicrotasks();
        h.app.voice.startListening(ListenSource.glasses); // soru bitmeden dokunuş
        async.elapse(const Duration(milliseconds: 500));
        expect(h.speech.lastSilenceTimeout, const Duration(milliseconds: 4500));
        h.dispose();
      });
    });
  });

  group('3) eşiğin hemen altındaki yakın aday belirsizlik sayılır', () {
    const contacts = [
      ContactEntry('a', 'Koray Yıldız', ['1']),
      ContactEntry('b', 'Kaan Yıldız', ['2']),
      ContactEntry('c', 'Okan Varol', ['3']),
    ];
    const matcher = ContactMatcher();

    test('logdaki durum: "Ayyıldız" -> 0,889 / 0,880 -> tahmin değil "hangisi?"', () {
      final m = matcher.match('Ayyıldız', contacts);
      expect(m, isA<ContactAmbiguous>(), reason: 'önceden Koray Yıldız seçiliyordu');
      expect([for (final c in (m as ContactAmbiguous).candidates) c.displayName],
          unorderedEquals(['Koray Yıldız', 'Kaan Yıldız']));
    });

    test('açık eşleşme etkilenmez', () {
      expect((matcher.match('Kaan Yıldız', contacts) as ContactFound).contact.displayName,
          'Kaan Yıldız');
      expect((matcher.match("Okan Varol'u", contacts) as ContactFound).contact.displayName,
          'Okan Varol');
    });

    test('en iyi aday eşiğin altındaysa yine bulunamadı', () {
      expect(matcher.match('Kıvanç Yıldızı', contacts), isA<ContactNotFound>());
    });
  });

  group('4) "sen/siz" kişi adına karışmaz', () {
    test('logdaki cümle', () {
      final cmd = classifyVoiceCommand("Kaan Yıldız'a mesaj göndersene sen bir");
      expect(cmd.intent, PatikaIntent.mesaj);
      expect(cmd.entity, 'Kaan Yıldız', reason: 'önceden "Kaan Yıldız Sen"');
    });
  });
}
