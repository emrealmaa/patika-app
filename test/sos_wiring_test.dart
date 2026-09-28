import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/feedback_sos_announcer.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/sos/sos_delivery.dart';
import 'package:patika_app/voice/voice_controller.dart';
import 'package:patika_app/widgets/sos_countdown_banner.dart';

import 'fakes.dart';
import 'test_harness.dart';

const ayse = EmergencyContact('Ayşe Demir', '0534 777 88 99');
const ali = EmergencyContact('Ali Kaya', '0533 444 55 66');
const testNumber = '0999 000 00 00';

/// Faz 7a-2: SOS'un uygulamaya bağlanması (gözlük dokunuşları, sesli iptal,
/// ekran, 112 teklifi, `play` davranışı). Zamanlama/karar mantığının kendisi
/// `sos_test.dart`'ta.
void main() {
  /// Saniye saniye ilerler; her saniye bekleyen konuşmaları bitirir.
  void advance(Harness h, FakeAsync async, int seconds) {
    for (var i = 0; i < seconds; i++) {
      async.elapse(const Duration(seconds: 1));
      h.speakAll(async);
    }
  }

  Harness direct({
    FakeDirectActions? actions,
    List<EmergencyContact> contacts = const [ayse, ali],
    Settings initial = const Settings(),
  }) =>
      Harness(
        direct: actions ?? FakeDirectActions(),
        emergencyContacts: contacts,
        initial: initial,
      );

  void longPress(Harness h, FakeAsync async) {
    h.app.simulator!.injectButton(GlassesButton.longPress);
    async.flushMicrotasks();
  }

  group('gözlük uzun basışı', () {
    test('geri sayımı başlatır; kimse iptal etmezse 7 sn sonra hepsine SMS + ilk kişi aranır', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);

        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.app.log.first.intent, PatikaIntent.sos);
        expect(h.tts.spoken.first, startsWith('Acil durum çağrısı gönderilecek'));
        expect(h.earcons.played, isNotEmpty);

        advance(h, async, 6);
        expect(actions.sms, isEmpty, reason: 'geri sayım bitmeden gitmez');

        advance(h, async, 5);
        expect(actions.sms.map((s) => s.$1), [ayse.number, ali.number]);
        expect(actions.calls, [ayse.number]);
        expect(h.tts.spoken.any((s) => s.contains('Acil durum mesajı 2 kişiye gönderildi')), isTrue);
        expect(h.tts.spoken.any((s) => s.contains('iletildi')), isFalse,
            reason: '"gönderildi" ile "iletildi" karıştırılmaz');
        h.dispose();
      });
    });

    test('geri sayımda TEK dokunuş iptal eder (dinlemeyi başlatmaz)', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 2);

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.tts.spoken.last, 'Acil durum çağrısı iptal edildi');

        advance(h, async, 30);
        expect(actions.sms, isEmpty);
        expect(actions.calls, isEmpty);
        h.dispose();
      });
    });

    test('geri sayımda ÇİFT dokunuş da iptal eder ("tekrar et" değil)', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        h.app.feedback.say('Önceki bir duyuru');
        h.speakAll(async);
        longPress(h, async);
        advance(h, async, 2);
        final before = h.tts.spoken.where((s) => s == 'Önceki bir duyuru').length;

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);

        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.tts.spoken.where((s) => s == 'Önceki bir duyuru').length, before,
            reason: 'çift dokunuş tekrar etmez, SOS\'u iptal eder');
        advance(h, async, 20);
        expect(actions.sms, isEmpty);
        h.dispose();
      });
    });

    test('telefon çalarken uzun basış SOS değil, aramayı reddeder (Faz 4b kararı)', () {
      fakeAsync((async) {
        final h = direct();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        async.flushMicrotasks();
        longPress(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('play sürümünde (doğrudan eylem yok) geri sayım başlamaz; hemen "gönderilemiyor" denir', () {
      fakeAsync((async) {
        final h = Harness(); // varsayılan: NoDirectActions
        longPress(h, async);
        h.speakAll(async);
        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.tts.spoken.first, startsWith('Bu sürümde acil durum mesajı gönderilemiyor'));
        expect(h.tts.spoken.first, contains('112'));
        h.dispose();
      });
    });
  });

  group('sesli komut', () {
    test('"yardım" geri sayımı başlatır', () {
      fakeAsync((async) {
        final h = direct();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(seconds: 1));
        h.speech.say('yardım');
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.earcons.played.last.name, isNot('success'),
            reason: 'SOS başlarken "başarılı" kısa sesi çalmaz');
        h.dispose();
      });
    });

    test('geri sayımda mikrofon sessizce açık kalır; "iptal" iptal eder', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 2);

        expect(h.speech.listening, isTrue, reason: 'giriş cümlesi bitince "iptal" için dinler');
        final listenEarcons = h.earcons.played.where((e) => e.name == 'listenStart');
        expect(listenEarcons, isEmpty, reason: 'SOS dinlemesinde "dinliyorum" sesi yok');

        h.speech.say('iptal');
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.tts.spoken.last, 'Acil durum çağrısı iptal edildi');
        advance(h, async, 30);
        expect(actions.sms, isEmpty);
        h.dispose();
      });
    });

    test('iptal listesi: iptal, iptal et, yanlış alarm, vazgeç, gerek yok', () {
      for (final phrase in ['iptal', 'iptal et', 'yanlış alarm', 'vazgeç', 'gerek yok', 'lütfen iptal']) {
        fakeAsync((async) {
          final h = direct();
          longPress(h, async);
          advance(h, async, 2);
          h.speech.say(phrase);
          async.flushMicrotasks();
          expect(h.app.sos.phase, SosPhase.idle, reason: '"$phrase" iptal etmeli');
          h.dispose();
        });
      }
    });

    test('"dur" geri sayımı iptal ETMEZ (yanlışlıkla iptal olan gerçek SOS çok daha kötü)', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 2);

        h.speech.say('dur');
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown);

        // Evrensel DUR komutu (başka yoldan gelse bile) SOS'u durdurmaz.
        h.app.submitVoiceCommand(BleCommand.fromWire('DUR', null));
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown);

        advance(h, async, 12);
        expect(actions.sms, hasLength(2), reason: 'SOS yine de gitti');
        h.dispose();
      });
    });

    test('alakasız konuşma ("saat kaç") geri sayımda hiçbir komut çalıştırmaz', () {
      fakeAsync((async) {
        final h = direct();
        longPress(h, async);
        advance(h, async, 2);
        final logged = h.app.log.length;
        h.speech.say('saat kaç');
        async.flushMicrotasks();
        expect(h.app.log.length, logged, reason: 'yalnızca iptal/gönder komutları anlaşılır');
        expect(h.app.sos.phase, SosPhase.countdown);
        h.dispose();
      });
    });

    test('"yardım" tetikleyicisi geri sayımı başlatınca aynı tanıma sonucunun az sonra '
        'yinelenmesi (tanıyıcı çift bildirimi) hemen göndermez', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        // Sesle tetikleme: "yardım" -> geri sayım başlar.
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(const Duration(seconds: 1));
        h.speech.say('yardım');
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown);

        // Tanıyıcının az sonra AYNI sonucu yinelemesi ihtimaline karşı: geri
        // sayımın hemen ardından gelen bir "yardım" (SOS dinlemesi henüz
        // açılmamış bile olsa, sonraki tik pencerede) hemen göndermemeli.
        async.elapse(const Duration(milliseconds: 300));
        h.app.sos.sendNow();
        async.flushMicrotasks();
        expect(actions.sms, isEmpty, reason: 'koruma süresi dolmadan gönderilmez');
        expect(h.app.sos.phase, SosPhase.countdown, reason: 'geri sayım sürmeye devam eder');
        h.dispose();
      });
    });

    test('geri sayımda "yardım" tekrarı beklemeden gönderir', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 2);
        h.speech.say('yardım');
        async.flushMicrotasks();
        advance(h, async, 3);
        expect(actions.sms, hasLength(2));
        h.dispose();
      });
    });

    test('sınıflandırıcı: iptal/gönder komutları yalnızca TÜM cümle eşleşirse', () {
      for (final t in ['iptal', 'İptal et', 'yanlış alarm', 'yanlış alarmdı', 'vazgeç', 'vazgeçtim', 'gerek yok']) {
        expect(classifySosVoice(t), SosVoiceCommand.cancel, reason: t);
      }
      for (final t in ['yardım', 'imdat', 'acil durum', 'gönder']) {
        expect(classifySosVoice(t), SosVoiceCommand.sendNow, reason: t);
      }
      for (final t in ['dur', 'durdur', 'sus', 'tamam', 'iptal etmeyin ama yardım', 'mesajı iptal et bence']) {
        expect(classifySosVoice(t), isNull, reason: '"$t" SOS komutu değil');
      }
    });
  });

  group('112', () {
    test('ayar açıksa yalnızca 112 aranır (testte enjekte edilen numara), kişi aranmaz', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions, initial: const Settings(emergencyCall112: true));
        longPress(h, async);
        advance(h, async, 12);
        expect(actions.calls, [testNumber]);
        expect(actions.sms, hasLength(2));
        expect(h.tts.spoken.any((s) => s.contains('Şimdi 112 aranıyor')), isTrue);
        h.dispose();
      });
    });

    test('SMS gitmediyse: "Gönderilemedi, 112\'yi aramak için çift dokunun"; çift dokunuş onaydır', () {
      fakeAsync((async) {
        final actions = FakeDirectActions()..smsResult = SmsSendStatus.failed;
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 7);
        h.speakAll(async);

        expect(
          h.tts.spoken.any((s) => s.startsWith("Gönderilemedi, 112'yi aramak için çift dokunun")),
          isTrue,
        );
        expect(h.app.sos.offering112, isTrue);
        expect(actions.calls, isEmpty, reason: 'pencere sürerken kimse aranmaz');
        final repeats = h.tts.spoken.length;

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);
        advance(h, async, 3);

        expect(h.tts.spoken.sublist(repeats), contains('112 aranıyor'));
        expect(actions.calls, [testNumber], reason: '112 onaylandı: ilk kişi aranmaz');
        h.dispose();
      });
    });

    test('pencerede onay yoksa ilk kişi aranır', () {
      fakeAsync((async) {
        final actions = FakeDirectActions()..smsResult = SmsSendStatus.failed;
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 7 + 1 + SosConfig.offerDecisionWindow.inSeconds + 2);
        expect(actions.calls, [ayse.number]);
        h.dispose();
      });
    });

    test('teklif yokken çift dokunuş her zamanki gibi "son duyuruyu tekrarlar"', () {
      fakeAsync((async) {
        final h = direct();
        h.app.feedback.say('Bir duyuru');
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.where((s) => s == 'Bir duyuru'), hasLength(2));
        h.dispose();
      });
    });

    test('acil kişi yoksa: "Acil kişi yok. 112\'yi aramak için çift dokunun"; çift dokunuş 112\'yi arar', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions, contacts: const []);
        longPress(h, async);
        h.speakAll(async);
        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.tts.spoken.first, "Acil kişi yok. 112'yi aramak için çift dokunun");
        expect(h.tts.spoken.first, isNot(contains('kurulu değil')));

        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        async.flushMicrotasks();
        h.speakAll(async);
        advance(h, async, 2);
        expect(actions.calls, [testNumber]);
        h.dispose();
      });
    });

    test('SMS izni yoksa SOS sessiz kalmaz: nedenini söyler', () {
      fakeAsync((async) {
        final h = direct();
        h.sosPermissions.sms = false;
        longPress(h, async);
        h.speakAll(async);
        expect(h.tts.spoken.first, startsWith('SMS izni yok, acil durum mesajı gönderilemez'));
        h.dispose();
      });
    });
  });

  group('AppState işlem geçmişi', () {
    test('SOS kayıtları yalnızca isim/sonuç durumu içerir, telefon numarası ya da konum yazılmaz', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        advance(h, async, 12);

        final sosEntries = h.app.log.where((e) => e.intent == PatikaIntent.sos).toList();
        expect(sosEntries, isNotEmpty);
        final text = sosEntries.map((e) => e.result.message).join('\n');
        expect(text, contains('Ayşe Demir'));
        expect(text, isNot(contains(ayse.number)));
        expect(text, isNot(contains(ali.number)));
        expect(text, isNot(contains('41.')));
        expect(text, isNot(contains('maps.google.com')));
        h.dispose();
      });
    });
  });

  group('gönderim başladıktan sonra', () {
    test('dokunuş "artık iptal edilemiyor" der', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        longPress(h, async);
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.sending);

        h.app.simulator!.injectButton(GlassesButton.tap);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.any((s) => s.startsWith('Gönderim başladı')), isTrue);
        h.dispose();
      });
    });
  });

  group('ekran şeridi', () {
    testWidgets('kalan süre ve büyük İptal düğmesi; dokununca iptal eder', (tester) async {
      final h = direct();
      addTearDown(h.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SosCountdownBanner(sos: h.app.sos)),
      ));
      expect(find.byType(FilledButton), findsNothing);

      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();
      expect(find.text('Acil durum çağrısı: 7 saniye sonra gönderilecek'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'İptal et, gönderme');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(56));

      await tester.tap(button);
      await tester.pump();
      expect(h.app.sos.phase, SosPhase.idle);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  test('eğitim metni: "Patika acil durum servisi değildir."', () {
    expect(Tr.tutorialSteps.join(' '), contains('Patika acil durum servisi değildir.'));
  });

  group('duyuru metinleri', () {
    const seven = SosCallTarget(name: 'Ayşe Demir');
    SosRecipientResult r(EmergencyContact c, SmsSendStatus s, {bool pending = false}) =>
        SosRecipientResult(c, s, pending: pending);

    test('hepsi gitti: "gönderildi" + kim aranacak', () {
      expect(
        FeedbackSosAnnouncer.resultsText([r(ayse, SmsSendStatus.sent), r(ali, SmsSendStatus.sent)],
            callTarget: seven, offer112: false),
        'Acil durum mesajı 2 kişiye gönderildi. Şimdi Ayşe Demir aranıyor',
      );
    });

    test('bir kişi: "bir kişiye"; 112 kendiliğinden aranacaksa onu söyler', () {
      expect(
        FeedbackSosAnnouncer.resultsText([r(ayse, SmsSendStatus.sent)],
            callTarget: const SosCallTarget(is112: true), offer112: false),
        'Acil durum mesajı bir kişiye gönderildi. Şimdi 112 aranıyor',
      );
    });

    test('hiçbiri gitmedi: kısa ve doğrudan; "gönderildi" geçmez', () {
      final text = FeedbackSosAnnouncer.resultsText(
        [r(ayse, SmsSendStatus.failed), r(ali, SmsSendStatus.timeout)],
        callTarget: seven,
        offer112: true,
      );
      expect(text, "Gönderilemedi, 112'yi aramak için çift dokunun, yoksa Ayşe Demir aranacak");
      expect(text, isNot(contains('gönderildi')));
    });

    test('bir kısmı gitti, biri gitmedi, biri bekliyor', () {
      final text = FeedbackSosAnnouncer.resultsText(
        [r(ayse, SmsSendStatus.sent), r(ali, SmsSendStatus.failed), r(ali, SmsSendStatus.timeout, pending: true)],
        callTarget: seven,
        offer112: false,
      );
      expect(text, contains('Acil durum mesajı bir kişiye gönderildi'));
      expect(text, contains('Bir kişiye gönderilemedi'));
      expect(text, contains('Bir kişi için sonuç bekleniyor'));
    });

    test('hiçbir yerde "iletildi" ya da "ulaştı" geçmez', () {
      final all = [
        FeedbackSosAnnouncer.resultsText([r(ayse, SmsSendStatus.sent)], callTarget: seven, offer112: false),
        FeedbackSosAnnouncer.resultsText([r(ayse, SmsSendStatus.failed)], callTarget: seven, offer112: true),
        FeedbackSosAnnouncer.afterCallText(
          SosReport(
            sms: [r(ayse, SmsSendStatus.failed)],
            call: const SosCallResult(SosCallOutcome.failed),
            locationIncluded: true,
          ),
          [r(ayse, SmsSendStatus.failed)],
        ),
      ];
      for (final t in all) {
        expect(t, isNot(contains('iletildi')));
        expect(t, isNot(contains('ulaştı')));
      }
    });

    test('arama sonrası özet: geç kalan sonuç ve başarısız arama', () {
      final report = SosReport(
        sms: [r(ayse, SmsSendStatus.sent), r(ali, SmsSendStatus.failed)],
        call: const SosCallResult(SosCallOutcome.failed, SosCallTarget(name: 'Ayşe Demir')),
        locationIncluded: true,
      );
      final text = FeedbackSosAnnouncer.afterCallText(report, [r(ali, SmsSendStatus.failed)]);
      expect(text, 'Ali Kaya için mesaj gönderilemedi. Arama başlatılamadı');
    });
  });
}
