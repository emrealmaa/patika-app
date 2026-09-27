import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'fakes.dart';
import 'test_harness.dart';

/// Faz 4b (son adım): "mesajlarımı oku", "son bildirimleri oku",
/// "bildirimleri sustur/aç".
void main() {
  const listenDelay = Duration(milliseconds: 500);

  void command(Harness h, FakeAsync async, String text) {
    h.app.voice.startListening(ListenSource.screen);
    async.elapse(listenDelay);
    h.speech.say(text);
    async.flushMicrotasks();
  }

  const ayse = IncomingMessage(
      senderName: 'Ayşe', body: 'Beş dakikaya oradayım', appPackage: 'com.whatsapp');
  const ahmet = IncomingMessage(senderName: 'Ahmet', body: 'Tamam', appPackage: 'com.whatsapp');

  group('sınıflandırıcı', () {
    test('mesajlarımı oku -> MESAJLARIM', () {
      for (final t in ['mesajlarımı oku', 'gelen mesajları oku', 'mesajları okur musun']) {
        expect(classifyVoiceCommand(t).intent, PatikaIntent.mesajlarim, reason: t);
      }
    });

    test('son bildirimleri oku -> SON_BİLDİRİMLER', () {
      for (final t in ['son bildirimleri oku', 'bildirimlerimi oku']) {
        expect(classifyVoiceCommand(t).intent, PatikaIntent.sonBildirimler, reason: t);
      }
    });

    test('gönderdiğim mesaj öncelikli kalır (MESAJLARIM değil)', () {
      expect(classifyVoiceCommand('gönderdiğim son mesajı oku').intent, PatikaIntent.sonMesaj);
    });

    test('bildirimleri sustur/aç -> AYAR', () {
      expect(classifyVoiceCommand('bildirimleri sustur').intent, PatikaIntent.ayar);
      expect(classifyVoiceCommand('bildirimleri aç').intent, PatikaIntent.ayar);
    });
  });

  group('mesajlarımı oku', () {
    test('okunmamış mesajları eskiden yeniye okur, sonra "yeni mesaj yok"', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(incomingMessages: incoming);
        incoming.emit(ayse);
        incoming.emit(ahmet);
        h.speakAll(async);
        h.tts.spoken.clear();

        command(h, async, 'mesajlarımı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last,
            "Ayşe'den mesaj: Beş dakikaya oradayım. Ahmet'ten mesaj: Tamam");

        h.tts.spoken.clear();
        command(h, async, 'mesajlarımı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Yeni mesaj yok');
        h.dispose();
      });
    });

    test('hiç mesaj gelmediyse "yeni mesaj yok"', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'mesajlarımı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Yeni mesaj yok');
        h.dispose();
      });
    });
  });

  group('son bildirimleri oku', () {
    test('göndereni özetler, okunmuş sayılmasını etkilemez', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(incomingMessages: incoming);
        incoming.emit(ayse);
        incoming.emit(ahmet);
        h.speakAll(async);
        h.tts.spoken.clear();

        command(h, async, 'son bildirimleri oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, "Son bildirimler: Ahmet'ten, Ayşe'den");

        // "mesajlarımı oku" hâlâ okunmamış sayıyor - son bildirimleri oku
        // onları "okunmuş" yapmadı.
        h.tts.spoken.clear();
        command(h, async, 'mesajlarımı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last,
            "Ayşe'den mesaj: Beş dakikaya oradayım. Ahmet'ten mesaj: Tamam");
        h.dispose();
      });
    });

    test('hiç bildirim yoksa "hiç bildirim yok"', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'son bildirimleri oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Hiç bildirim yok');
        h.dispose();
      });
    });
  });

  group('bildirimleri sustur/aç', () {
    test('susturunca gelen mesaj duyurulmaz ama günlüğe eklenir', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(incomingMessages: incoming);
        command(h, async, 'bildirimleri sustur');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Bildirimler susturuldu');
        expect(h.app.settings.value.notificationsMuted, isTrue);

        h.tts.spoken.clear();
        incoming.emit(ayse);
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty, reason: 'susturulmuşken hiç duyuru olmamalı');

        command(h, async, 'mesajlarımı oku');
        h.speakAll(async);
        expect(h.tts.spoken.last, "Ayşe'den mesaj: Beş dakikaya oradayım",
            reason: 'susturulmuş olsa da günlüğe eklenmiş olmalı');
        h.dispose();
      });
    });

    test('açınca sonraki mesaj yine duyurulur', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(
          initial: const Settings(notificationsMuted: true),
          incomingMessages: incoming,
        );
        command(h, async, 'bildirimleri aç');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Bildirimler açıldı');

        h.tts.spoken.clear();
        incoming.emit(ayse);
        h.speakAll(async);
        expect(h.tts.spoken, contains("Ayşe'den mesaj: Beş dakikaya oradayım"));
        h.dispose();
      });
    });
  });
}
