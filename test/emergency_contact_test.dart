import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'fakes.dart';
import 'test_harness.dart';

const listenDelay = Duration(milliseconds: 500);

/// Komutu tetikleyiciyle verir (Konuş butonu) - `dialog_test.dart` ile aynı desen.
void command(Harness h, FakeAsync async, String text) {
  h.app.voice.startListening(ListenSource.screen);
  async.elapse(listenDelay);
  h.speech.say(text);
  async.flushMicrotasks();
}

/// Sorunun bitmesini bekler, tetikleyicisiz dinlemeyi doğrular, cevabı verir.
void answer(Harness h, FakeAsync async, String text) {
  h.speakAll(async);
  async.elapse(listenDelay);
  expect(h.speech.listening, isTrue, reason: 'soru bitince dinleme açılmalı ("$text" öncesi)');
  h.speech.say(text);
  async.flushMicrotasks();
}

void main() {
  group('sınıflandırıcı: ACİL_KİŞİ', () {
    void expectWire(String text, String entity) {
      final cmd = classifyVoiceCommand(text);
      expect(cmd.intent, PatikaIntent.acilKisi, reason: '"$text" niyeti');
      expect(cmd.entity, entity, reason: '"$text" entity');
    }

    test('liste: birkaç doğal söyleyiş', () {
      for (final text in ['acil kişiler kim', 'acil kişi kim', 'acil kişilerimi oku', 'acil kişi listele']) {
        expectWire(text, 'liste');
      }
    });

    test('ekle: fiil isimden önce', () => expectWire('acil kişi ekle Ayşe', 'ekle|Ayşe'));

    test('ekle: isim fiilden önce (belirtme ekiyle)',
        () => expectWire("Ayşe'yi acil kişi ekle", 'ekle|Ayşe'));

    test('ekle: "olarak" araya girse de', () => expectWire('acil kişi olarak Ayşe ekle', 'ekle|Ayşe'));

    test('ekle: isim yoksa boş entity', () => expectWire('acil kişi ekle', 'ekle|'));

    test('sil: fiil isimden önce', () => expectWire('acil kişi sil Ayşe', 'sil|Ayşe'));

    test('sil: "çıkar" ve isim araya girse de',
        () => expectWire("acil kişilerden Ayşe'yi çıkar", 'sil|Ayşe'));

    test('"acil" geçen ama kişiyle ilgisiz cümleler ACİL_KİŞİ değil', () {
      expect(classifyVoiceCommand('acil durum').intent, PatikaIntent.sos);
      expect(classifyVoiceCommand('yardım').intent, PatikaIntent.sos);
    });

    test('komşu niyetler bozulmadı', () {
      expect(classifyVoiceCommand("Ahmet'i ara").intent, PatikaIntent.ara);
      expect(classifyVoiceCommand('annemi Fatma Yılmaz olarak kaydet').intent, PatikaIntent.takmaAd);
    });

    test('wire adları', () {
      expect(PatikaIntent.fromWireName('ACIL_KISI'), PatikaIntent.acilKisi);
      expect(PatikaIntent.fromWireName('ACIL_KİŞİ'), PatikaIntent.acilKisi);
    });
  });

  group('acil kişi ekle (diyalog)', () {
    test('tarifteki örnek: ekle Ayşe -> onay -> evet -> eklendi (play: SMS izni hiç istenmez)', () {
      fakeAsync((async) {
        final h = Harness(); // play: NoDirectActions
        command(h, async, 'acil kişi ekle Ayşe');
        expect(h.tts.spoken, [Tr.dialogConfirmEmergencyAdd("Ayşe Demir'i")]);

        answer(h, async, 'evet');
        h.speakAll(async);

        expect(h.tts.spoken.last, 'Ayşe Demir acil kişi olarak eklendi');
        expect(contactsOf(h, async).map((c) => c.name), ['Ayşe Demir']);
        expect(h.app.log.first.intent, PatikaIntent.acilKisi);
        h.dispose();
      });
    });

    test('isim verilmeden: "Kimi ekleyeyim?" sorar', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişi ekle');
        expect(h.tts.spoken, [Tr.dialogWhoToAddEmergency]);
        answer(h, async, 'Ayşe');
        expect(h.tts.spoken.last, Tr.dialogConfirmEmergencyAdd("Ayşe Demir'i"));
        h.dispose();
      });
    });

    test('iki Ahmet: "hangisi?" diye sorar', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişi ekle Ahmet');
        expect(h.tts.spoken.last, contains('Hangisi?'));
        answer(h, async, 'ikinci');
        expect(h.tts.spoken.last, Tr.dialogConfirmEmergencyAdd('Ahmet Kaya\'yı'));
        h.dispose();
      });
    });

    test('hayır: eklenmez', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.dialogCancelled);
        expect(contactsOf(h, async), isEmpty);
        h.dispose();
      });
    });

    test('rehberde yok: bulunamadı der, eklenmez', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişi ekle Zeynep');
        h.speakAll(async);
        expect(h.tts.spoken.last, contains('rehberde bulamadım'));
        expect(contactsOf(h, async), isEmpty);
        h.dispose();
      });
    });

    test('zaten ekli: "zaten acil kişi" der, mükerrer eklenmez', () {
      fakeAsync((async) {
        final h = Harness(emergencyContacts: const [
          EmergencyContact('Ayşe Demir', '0534 777 88 99'),
        ]);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Ayşe Demir zaten acil kişi');
        expect(contactsOf(h, async), hasLength(1));
        h.dispose();
      });
    });

    test('3 kişi doluyken: "en fazla 3" der, eklenmez', () {
      fakeAsync((async) {
        final h = Harness(emergencyContacts: const [
          EmergencyContact('Ahmet Yılmaz', '0532 111 22 33'),
          EmergencyContact('Ahmet Kaya', '0533 444 55 66'),
          EmergencyContact('Annem', '0537 666 77 88'),
        ]);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.emergencyContactListFull);
        expect(contactsOf(h, async), hasLength(3));
        h.dispose();
      });
    });

  });

  group('acil kişi ekle: SMS izni ve isteğe bağlı rıza SMS\'i (yalnızca direct)', () {
    test('play: SMS izni hiç istenmez, rıza sorusu hiç sorulmaz', () {
      fakeAsync((async) {
        var asked = 0;
        final h = Harness(ensureSmsPermission: () async {
          asked++;
          return true;
        });
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(asked, 0, reason: 'play sürümünde SMS gönderilemez, izin de istenmez');
        expect(h.tts.spoken.last, isNot(contains('mesaj')));
        h.dispose();
      });
    });

    test('direct: eklenince SMS izni istenir; verilirse rıza sorusu sorulur', () {
      fakeAsync((async) {
        var asked = 0;
        final actions = FakeDirectActions();
        final h = Harness(
          direct: actions,
          ensureSmsPermission: () async {
            asked++;
            return true;
          },
        );
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(asked, 1);
        expect(h.tts.spoken.last, contains('bildiren bir mesaj göndereyim mi'));
        expect(actions.sms, isEmpty, reason: 'onay verilmeden SMS gitmez');
        h.dispose();
      });
    });

    test('rıza sorusuna evet: SMS gider (sahte teslimat), detayda "gönderildi" geçer', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(direct: actions);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(actions.sms.single.$1, '0534 777 88 99');
        expect(actions.sms.single.$2, Tr.emergencyConsentSmsBody);
        expect(h.tts.spoken.last, contains('bildirim mesajı gönderildi'));
        h.dispose();
      });
    });

    test('rıza sorusuna hayır: SMS gitmez, yine de eklenmiş sayılır', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(direct: actions);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(actions.sms, isEmpty);
        expect(h.tts.spoken.last, 'Ayşe Demir acil kişi olarak eklendi');
        expect(contactsOf(h, async), hasLength(1));
        h.dispose();
      });
    });

    test('SMS izni verilmezse rıza sorusu hiç sorulmaz, neden söylenir', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(direct: actions, ensureSmsPermission: () async => false);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.tts.spoken.last, contains('SMS izni verilmedi'));
        expect(actions.sms, isEmpty);
        expect(contactsOf(h, async), hasLength(1), reason: 'izin olmasa da kişi eklenir');
        h.dispose();
      });
    });

    test('rıza SMS\'i testte gerçek numaraya değil, yalnızca sahte teslimata gider', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(direct: actions);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        answer(h, async, 'evet');
        h.speakAll(async);
        // FakeDirectActions hiçbir platform kanalına dokunmaz; 112'ye giden
        // hiçbir şey yok (ayrıca sabit kilitli, bkz. fakes.dart).
        expect(actions.calls, isEmpty);
        h.dispose();
      });
    });
  });

  group('acil kişi sil (diyalog)', () {
    Harness withTwo() => Harness(emergencyContacts: const [
          EmergencyContact('Ayşe Demir', '0534 777 88 99'),
          EmergencyContact('Ali Kaya', '0533 444 55 66'),
        ]);

    test('isimle: onay -> evet -> silinir', () {
      fakeAsync((async) {
        final h = withTwo();
        command(h, async, 'acil kişi sil Ayşe');
        expect(h.tts.spoken, [Tr.dialogConfirmEmergencyRemove("Ayşe Demir'i")]);
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Ayşe Demir acil kişilerden çıkarıldı');
        expect(contactsOf(h, async).map((c) => c.name), ['Ali Kaya']);
        h.dispose();
      });
    });

    test('isim yoksa mevcut kişileri sorar', () {
      fakeAsync((async) {
        final h = withTwo();
        command(h, async, 'acil kişi sil');
        expect(h.tts.spoken.last, contains('Hangisi?'));
        expect(h.tts.spoken.last, contains('Ayşe Demir'));
        expect(h.tts.spoken.last, contains('Ali Kaya'));
        answer(h, async, 'birinci');
        expect(h.tts.spoken.last, Tr.dialogConfirmEmergencyRemove("Ayşe Demir'i"));
        h.dispose();
      });
    });

    test('bulunamayan isim: mevcut kişiler söylenir, silinmez', () {
      fakeAsync((async) {
        final h = withTwo();
        command(h, async, 'acil kişi sil Zeynep');
        h.speakAll(async);
        expect(h.tts.spoken.last, contains('acil kişilerinizde yok'));
        expect(h.tts.spoken.last, contains('Ayşe Demir'));
        expect(contactsOf(h, async), hasLength(2));
        h.dispose();
      });
    });

    test('hayır: silinmez', () {
      fakeAsync((async) {
        final h = withTwo();
        command(h, async, 'acil kişi sil Ayşe');
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.dialogCancelled);
        expect(contactsOf(h, async), hasLength(2));
        h.dispose();
      });
    });

    test('hiç acil kişi yokken: "hiç acil kişiniz yok" der, diyalog açmaz', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişi sil');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.emergencyContactListEmpty);
        expect(h.app.dialogs.active, isFalse);
        h.dispose();
      });
    });
  });

  group('acil kişiler kim (diyalogsuz)', () {
    test('kayıtlı kişileri okur', () {
      fakeAsync((async) {
        final h = Harness(emergencyContacts: const [
          EmergencyContact('Ayşe Demir', '0534 777 88 99'),
          EmergencyContact('Ali Kaya', '0533 444 55 66'),
        ]);
        command(h, async, 'acil kişiler kim');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Acil kişileriniz: Ayşe Demir, Ali Kaya');
        expect(h.app.dialogs.active, isFalse, reason: 'liste diyalog açmaz, tek adımda cevaplar');
        h.dispose();
      });
    });

    test('hiç yoksa yönlendirir', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'acil kişiler kim');
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.emergencyContactListEmpty);
        h.dispose();
      });
    });
  });

  group('SOS ile tutarlılık', () {
    test('acil kişi eklendikten sonra SOS o kişiye gönderir (uçtan uca, sahte teslimat)', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(direct: actions);
        command(h, async, 'acil kişi ekle Ayşe');
        answer(h, async, 'evet');
        answer(h, async, 'hayır'); // rıza SMS'i istemiyoruz, testin odağı SOS
        h.speakAll(async);

        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.flushMicrotasks();
        for (var i = 0; i < 12; i++) {
          async.elapse(const Duration(seconds: 1));
          h.speakAll(async);
        }
        expect(actions.sms.any((s) => s.$1 == '0534 777 88 99'), isTrue);
        expect(actions.calls, ['0534 777 88 99']);
        h.dispose();
      });
    });
  });

  test('testlerin sahte DirectActions\'ı 112\'ye SMS ya da arama göndermez (koruma)', () {
    final direct = FakeDirectActions();
    expect(() => direct.sendSms('112', Tr.emergencyConsentSmsBody), throwsStateError);
    expect(() => direct.call('112'), throwsStateError);
  });
}

/// `h.emergencyContacts.readAll()`in fakeAsync içinde okunması: Future
/// senkron hesaplanıyor ama `then()` yine de bir mikro görev; bekleyen
/// mikro görevleri akıtıp sonucu döndürür.
List<EmergencyContact> contactsOf(Harness h, FakeAsync async) {
  List<EmergencyContact>? result;
  h.emergencyContacts.readAll().then((v) => result = v);
  async.flushMicrotasks();
  return result!;
}
