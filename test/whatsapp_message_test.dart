import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/handlers/message_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/message_app.dart';
import 'package:patika_app/commands/sent_messages.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'fakes.dart';
import 'test_harness.dart';

/// MESAJ: WhatsApp (komutla ya da Ayarlar'daki varsayılan).
void main() {
  const ayse = ContactEntry('3', 'Ayşe Demir', ['0555 000 00 03']);
  const listenDelay = Duration(milliseconds: 500);

  group('whatsappNumber', () {
    test('Türkiye numaraları 90 ile başlar', () {
      expect(whatsappNumber('0555 000 00 03'), '905550000003');
      expect(whatsappNumber('555 000 00 03'), '905550000003');
      expect(whatsappNumber('+90 555 000 00 03'), '905550000003');
      expect(whatsappNumber('0090 555 000 00 03'), '905550000003');
    });

    test('başka ülke kodu korunur; rakam yoksa null', () {
      expect(whatsappNumber('+49 151 2345678'), '491512345678');
      expect(whatsappNumber('-'), isNull);
    });
  });

  group('sınıflandırıcı', () {
    void expectWhatsapp(String text, String entity) {
      final c = classifyVoiceCommand(text);
      expect(c.intent, PatikaIntent.mesaj, reason: text);
      expect(c.entity, entity, reason: text);
      expect(c.messageApp, MessageApp.whatsapp, reason: text);
    }

    test('WhatsApp geçen mesaj komutları', () {
      expectWhatsapp("Ayşe'ye WhatsApp'tan mesaj gönder", 'Ayşe');
      expectWhatsapp("WhatsApp'tan Ayşe'ye mesaj at", 'Ayşe');
      expectWhatsapp("WhatsApp at Ayşe'ye", 'Ayşe');
      expectWhatsapp('anneme vatsaptan yaz', 'annem');
      expectWhatsapp("Ayşe'ye whats app'tan mesaj yolla", 'Ayşe');
      // iOS STT "WhatsApp'tan"ı böyle yazdı (gerçek cihaz, 2026-10-15).
      expectWhatsapp("Ayşe'ye Whatsatan mesaj gönder", 'Ayşe');
      expectWhatsapp('anneme votsaptan mesaj at', 'annem');
    });

    test('benzer Türkçe kelimeler WhatsApp sayılmaz', () {
      for (final t in ["Vatan'a mesaj gönder", "Ayşe'ye vatandaşlık mesajı gönder"]) {
        expect(classifyVoiceCommand(t).messageApp, isNull, reason: t);
      }
    });

    test('WhatsApp geçmeyen mesaj: uygulama ayara kalır', () {
      final c = classifyVoiceCommand("Ayşe'ye mesaj gönder");
      expect(c.intent, PatikaIntent.mesaj);
      expect(c.messageApp, isNull);
    });

    test('WhatsApp araması yok: normal ARA, WhatsApp kişi adına girmez', () {
      final c = classifyVoiceCommand("WhatsApp'tan Ayşe'yi ara");
      expect(c.intent, PatikaIntent.ara);
      expect(c.entity, 'Ayşe');
      expect(c.messageApp, isNull);
    });
  });

  group('gönderim', () {
    test('sohbet metin dolu açılır; "gönderildi" denmez', () async {
      final opened = <Uri>[];
      final log = SentMessageLog();
      final handler = MessageHandler(
        sent: log,
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      );
      final result = await handler.send(ayse, 'Geliyorum, 5 dk', app: MessageApp.whatsapp);
      expect(opened.single.toString(), 'whatsapp://send?phone=905550000003&text=Geliyorum%2C%205%20dk');
      expect(result.message, Tr.whatsappReady('Ayşe Demir'));
      expect(result.detail, Tr.whatsappReadyDetail);
      expect(log.last!.confirmedSent, isFalse);
    });

    test('WhatsApp açılamazsa nedeni söylenir, son mesaj sayılmaz', () async {
      final log = SentMessageLog();
      final handler = MessageHandler(sent: log, openUrl: (_) async => false);
      final result = await handler.send(ayse, 'Geliyorum', app: MessageApp.whatsapp);
      expect(result.success, isFalse);
      expect(result.message, Tr.whatsappFailed);
      expect(result.detail, Tr.whatsappFailedDetail);
      expect(log.last, isNull);
    });

    test('direct türünde de WhatsApp doğrudan SMS göndermez', () async {
      final direct = FakeDirectActions();
      final opened = <Uri>[];
      final handler = MessageHandler(
        direct: direct,
        ensureSmsPermission: () async => true,
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      );
      await handler.send(ayse, 'Geliyorum', app: MessageApp.whatsapp);
      expect(direct.sms, isEmpty);
      expect(opened.single.scheme, 'whatsapp');
    });
  });

  group('uçtan uca (diyalog)', () {
    void say(Harness h, FakeAsync async, String text, {bool first = false}) {
      if (first) {
        h.app.voice.startListening(ListenSource.screen);
      } else {
        h.speakAll(async);
      }
      async.elapse(listenDelay);
      h.speech.say(text);
      async.flushMicrotasks();
    }

    void sendMessage(Harness h, FakeAsync async, String command) {
      say(h, async, command, first: true);
      say(h, async, 'Geliyorum');
      say(h, async, 'evet');
      h.speakAll(async);
    }

    test('komutta WhatsApp: geri okumada söylenir, WhatsApp açılır', () {
      fakeAsync((async) {
        final h = Harness();
        sendMessage(h, async, "Ayşe'ye WhatsApp'tan mesaj gönder");
        expect(h.tts.spoken, contains(startsWith("WhatsApp'tan Ayşe Demir'e şu mesaj")));
        expect(h.opened.single.scheme, 'whatsapp');
        h.dispose();
      });
    });

    test('ayar WhatsApp: düz "mesaj gönder" WhatsApp\'tan gider', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(messageApp: MessageApp.whatsapp));
        sendMessage(h, async, "Ayşe'ye mesaj gönder");
        expect(h.opened.single.scheme, 'whatsapp');
        h.dispose();
      });
    });

    test('ayar SMS (varsayılan): düz "mesaj gönder" SMS', () {
      fakeAsync((async) {
        final h = Harness();
        sendMessage(h, async, "Ayşe'ye mesaj gönder");
        expect(h.opened.single.scheme, 'sms');
        h.dispose();
      });
    });
  });
}
