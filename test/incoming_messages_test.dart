import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/settings/settings.dart';

import 'fakes.dart';
import 'test_harness.dart';

void main() {
  group('gelen mesaj duyurusu (Faz 4b)', () {
    const message = IncomingMessage(
      senderName: 'Ayşe',
      body: 'Beş dakikaya oradayım',
      appPackage: 'com.whatsapp',
    );

    test('açıkken: önce bir kerelik gizlilik uyarısı, sonra "kimden mesaj: içerik"', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(incomingMessages: incoming);
        incoming.emit(message);
        h.speakAll(async);

        expect(h.tts.spoken, [
          'Mesaj içerikleri yüksek sesle okunuyor, kalabalık ortamda dikkat '
              'edin, ayarlardan kapatabilirsiniz.',
          "Ayşe'den mesaj: Beş dakikaya oradayım",
        ]);
        h.dispose();
      });
    });

    test('ikinci mesajda gizlilik uyarısı tekrarlanmaz', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(incomingMessages: incoming);
        incoming.emit(message);
        h.speakAll(async);
        h.tts.spoken.clear();

        incoming.emit(const IncomingMessage(
          senderName: 'Ahmet',
          body: 'Tamam',
          appPackage: 'com.whatsapp',
        ));
        h.speakAll(async);

        expect(h.tts.spoken, ["Ahmet'ten mesaj: Tamam"]);
        h.dispose();
      });
    });

    test('kapalıyken: yalnızca kimden geldiği söylenir, içerik okunmaz, uyarı yok', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(
          initial: const Settings(readMessagesAloud: false),
          incomingMessages: incoming,
        );
        incoming.emit(message);
        h.speakAll(async);

        expect(h.tts.spoken, ["Ayşe'den yeni mesaj"]);
        h.dispose();
      });
    });

    test('daha önce gösterilmiş uyarı bir daha söylenmez (kalıcı durum)', () {
      fakeAsync((async) {
        final incoming = FakeIncomingMessages();
        final h = Harness(
          incomingMessages: incoming,
          loudMessagesNotice: MemoryLoudMessagesNotice(true),
        );
        incoming.emit(message);
        h.speakAll(async);

        expect(h.tts.spoken, ["Ayşe'den mesaj: Beş dakikaya oradayım"]);
        h.dispose();
      });
    });
  });
}
