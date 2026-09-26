import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/handlers/call_handler.dart';
import 'package:patika_app/commands/handlers/message_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/sent_messages.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'fakes.dart';
import 'test_harness.dart';

/// Faz 4a: "play" ve "direct" derleme türleri.
void main() {
  const ayse = ContactEntry('3', 'Ayşe Demir', ['0534 777 88 99']);
  const listenDelay = Duration(milliseconds: 500);

  void command(Harness h, FakeAsync async, String text) {
    h.app.voice.startListening(ListenSource.screen);
    async.elapse(listenDelay);
    h.speech.say(text);
    async.flushMicrotasks();
  }

  void answer(Harness h, FakeAsync async, String text) {
    h.speakAll(async);
    async.elapse(listenDelay);
    h.speech.say(text);
    async.flushMicrotasks();
  }

  group('ARA', () {
    test('direct: onaydan sonra doğrudan arar, ekran açılmaz', () {
      fakeAsync((async) {
        final direct = FakeDirectActions();
        final h = Harness(direct: direct);
        command(h, async, "Ayşe'yi ara");
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(direct.calls, ['05347778899']);
        expect(h.opened, isEmpty);
        expect(h.tts.spoken.last, 'Ayşe Demir aranıyor');
        h.dispose();
      });
    });

    test('play: arama ekranı açılır (doğrudan arama yok)', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ayşe'yi ara");
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.opened.single.toString(), 'tel:05347778899');
        h.dispose();
      });
    });

    test('direct ama izin reddedildi: ekran açılır ve bu söylenir', () async {
      final direct = FakeDirectActions();
      final opened = <Uri>[];
      final handler = CallHandler(
        direct: direct,
        ensureCallPermission: () async => false,
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      );
      final result = await handler.dial(ayse);
      expect(direct.calls, isEmpty);
      expect(opened.single.scheme, 'tel');
      expect(result.detail, Tr.directPermissionFallback);
    });

    test('direct ama arama başlatılamadı: ekrana düşer', () async {
      final direct = FakeDirectActions()..callSucceeds = false;
      final opened = <Uri>[];
      final handler = CallHandler(
        direct: direct,
        ensureCallPermission: () async => true,
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      );
      final result = await handler.dial(ayse);
      expect(opened, hasLength(1));
      expect(result.message, Tr.dialerOpened('Ayşe Demir'));
    });
  });

  group('MESAJ', () {
    MessageHandler handlerWith(FakeDirectActions direct, List<Uri> opened, SentMessageLog log,
            {bool permission = true}) =>
        MessageHandler(
          direct: direct,
          ensureSmsPermission: () async => permission,
          sent: log,
          openUrl: (u) async {
            opened.add(u);
            return true;
          },
        );

    test('direct: doğrudan gönderilir, operatör onayından sonra "gönderildi"', () async {
      final direct = FakeDirectActions();
      final opened = <Uri>[];
      final log = SentMessageLog();
      final result = await handlerWith(direct, opened, log).send(ayse, 'Geliyorum');
      expect(direct.sms.single, ('05347778899', 'Geliyorum'));
      expect(opened, isEmpty);
      expect(result.message, "Ayşe Demir'e mesaj gönderildi");
      expect(log.last!.confirmedSent, isTrue);
    });

    test('direct: gönderilemedi -> "gönderildi" DENMEZ, son mesaj sayılmaz', () async {
      final direct = FakeDirectActions()..smsResult = SmsSendStatus.failed;
      final log = SentMessageLog();
      final result = await handlerWith(direct, [], log).send(ayse, 'Geliyorum');
      expect(result.success, isFalse);
      expect(result.message, Tr.smsSendFailed);
      expect(log.last, isNull);
    });

    test('direct: operatör cevap vermedi -> doğrulanamadı', () async {
      final direct = FakeDirectActions()..smsResult = SmsSendStatus.timeout;
      final result = await handlerWith(direct, [], SentMessageLog()).send(ayse, 'Geliyorum');
      expect(result.message, Tr.smsSendTimeout);
    });

    test('direct ama izin reddedildi: ekran metin dolu açılır', () async {
      final direct = FakeDirectActions();
      final opened = <Uri>[];
      final result = await handlerWith(direct, opened, SentMessageLog(), permission: false)
          .send(ayse, 'Geliyorum');
      expect(direct.sms, isEmpty);
      expect(opened.single.scheme, 'sms');
      expect(result.detail, Tr.directPermissionFallback);
    });

    test('play: diyalogla ekran dolu açılır, son mesaj "hazırlanan" olarak okunur', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, "Ayşe'ye mesaj gönder");
        answer(h, async, 'Geliyorum');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.opened.single.scheme, 'sms');

        command(h, async, 'gönderdiğim son mesajı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, startsWith('Ayşe Demir için hazırlanan son mesaj: Geliyorum'));
        h.dispose();
      });
    });

    test('direct: diyalogla gönderilir, son mesaj "gönderilen" olarak okunur', () {
      fakeAsync((async) {
        final direct = FakeDirectActions();
        final h = Harness(direct: direct);
        command(h, async, "Ayşe'ye mesaj gönder");
        answer(h, async, 'Geliyorum');
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(direct.sms.single.$2, 'Geliyorum');

        command(h, async, 'son gönderdiğim mesaj ne');
        h.speakAll(async);
        expect(h.tts.spoken.last, "Ayşe Demir'e gönderilen son mesaj: Geliyorum");
        h.dispose();
      });
    });

    test('henüz mesaj yoksa bu söylenir', () async {
      final result = await LastMessageHandler(SentMessageLog()).handle();
      expect(result.message, Tr.lastSentNone);
    });
  });

  test('sınıflandırıcı: gönderilen son mesaj', () {
    for (final t in [
      'gönderdiğim son mesajı oku',
      'son gönderdiğim mesaj ne',
      'gönderdiğim mesajı tekrar oku',
    ]) {
      expect(classifyVoiceCommand(t).intent, PatikaIntent.sonMesaj, reason: t);
    }
    expect(classifyVoiceCommand("Ayşe'ye mesaj gönder").intent, PatikaIntent.mesaj);
  });
}
