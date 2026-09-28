import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/navigation/place_search.dart';
import 'package:patika_app/navigation/route.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'fakes.dart';
import 'navigation_fixtures.dart';
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

  /// Sorunun bitmesini bekler, dinlemenin tetikleyicisiz açıldığını doğrular
  /// ve cevabı verir.
  void answer(Harness h, FakeAsync async, String text) {
    h.speakAll(async);
    async.elapse(listenDelay);
    expect(h.speech.listening, isTrue, reason: 'soru bitince dinleme açılmalı ("$text" öncesi)');
    h.speech.say(text);
    async.flushMicrotasks();
  }

  /// Google Routes'ın döndürdüğü gibi sokak adsız rota (bkz. google_parsing.dart).
  WalkingRoute namelessRoute() {
    final r = testRoute();
    return WalkingRoute(
      destinationName: r.destinationName,
      duration: r.duration,
      steps: [
        for (final s in r.steps)
          RouteStep(maneuver: s.maneuver, points: s.points, isCrossing: s.isCrossing),
      ],
    );
  }

  final iskele = PlaceCandidate(
    name: 'Kadıköy İskelesi',
    address: 'Osmanağa, Kadıköy',
    location: enu(170, 300),
  );

  /// Gerçek mod: Google istemcileri (sahte) + konum + izin tamam.
  ({Harness h, FakePlanner planner, FakePlaceSearch places}) realHarness({
    List<PlaceCandidate>? found,
    bool haveFix = true,
  }) {
    final planner = FakePlanner()..result = namelessRoute();
    final places = FakePlaceSearch(found ?? [iskele]);
    final h = Harness(routePlanner: planner, placeSearch: places);
    if (haveFix) h.location.emit(enu(0, 0));
    return (h: h, planner: planner, places: places);
  }

  group('gerçek mod (Google anahtarı + konum hazır)', () {
    test('yer -> rota -> onay -> "evet": uygulama içi navigasyon başlar', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        command(h, async, 'Kadıköy iskelesine götür');

        expect(h.tts.spoken, ['Kadıköy İskelesi, 450 metre, yaklaşık 6 dakika. Başlayayım mı?']);
        expect(places.calls.single.query, 'Kadıköy iskelesi');
        expect(places.calls.single.near, enu(0, 0), reason: 'yakın sonuç önceliği için kalkış noktası');
        expect(planner.calls.single.from, enu(0, 0));
        expect(planner.calls.single.to, enu(170, 300));
        expect(planner.calls.single.name, 'Kadıköy İskelesi');
        expect(h.app.navigation.active, isFalse, reason: 'onaydan önce başlamaz');

        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Navigasyon başladı. Yön bilgisi yürümeye başlayınca gelecek');
        expect(h.app.navigation.active, isTrue);
        expect(h.location.isRunning, isTrue);
        expect(h.opened, isEmpty, reason: 'harita uygulaması açılmaz');
        expect(h.app.log.first.intent, PatikaIntent.navigasyon);
        expect(h.app.log.first.entity, 'Kadıköy İskelesi');
        h.dispose();
      });
    });

    test('"hayır": hiçbir şey başlamaz', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        command(h, async, 'Kadıköy iskelesine götür');
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'İptal ettim');
        expect(h.app.navigation.active, isFalse);
        expect(h.opened, isEmpty);
        h.dispose();
      });
    });

    test('birden çok yer: "hangisi?", "ikinci" -> o yerin rotası', () {
      fakeAsync((async) {
        final second = PlaceCandidate(name: 'Kadıköy Meydanı', location: enu(500, 500));
        final (:h, :planner, :places) = realHarness(found: [iskele, second]);
        command(h, async, 'Kadıköy götür');
        expect(h.tts.spoken.last,
            'İki yer buldum: birinci Kadıköy İskelesi, ikinci Kadıköy Meydanı. Hangisi?');

        answer(h, async, 'ikinci');
        expect(planner.calls.single.to, enu(500, 500));
        expect(planner.calls.single.name, 'Kadıköy Meydanı');
        expect(h.tts.spoken.last, contains('Başlayayım mı?'));
        h.dispose();
      });
    });

    test('yer bulunamazsa bir kez daha sorar, ikincide iptal eder', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness(found: []);
        command(h, async, 'Zzz durağına götür');
        expect(h.tts.spoken.last, 'Zzz durağı adında bir yer bulamadım. Nereye gitmek istiyorsunuz?');

        answer(h, async, 'Yyy');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Yyy adında bir yer bulamadım');
        expect(h.app.dialogs.active, isFalse);
        expect(planner.calls, isEmpty);
        h.dispose();
      });
    });

    test('yer söylenmemişse "Nereye gitmek istiyorsunuz?" diye sorar', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        h.app.submitVoiceCommand(BleCommand.fromWire('NAVİGASYON', null));
        async.flushMicrotasks();
        expect(h.tts.spoken, ['Nereye gitmek istiyorsunuz?']);

        answer(h, async, 'Kadıköy iskelesi');
        expect(h.tts.spoken.last, contains('Başlayayım mı?'));
        h.dispose();
      });
    });

    test('anlaşılamayan onay cevabı bir kez ipucuyla tekrar sorulur, sonra iptal', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        command(h, async, 'Kadıköy iskelesine götür');
        answer(h, async, 'belki');
        expect(h.tts.spoken.last,
            'Evet ya da hayır deyin. Kadıköy İskelesi, 450 metre, yaklaşık 6 dakika. Başlayayım mı?');
        answer(h, async, 'belki');
        h.speakAll(async);
        expect(h.tts.spoken.last, 'Anlayamadım, iptal ettim');
        expect(h.app.navigation.active, isFalse);
        h.dispose();
      });
    });
  });

  group('yedek akış: Google Haritalar', () {
    test('anahtar yok: sessizce harita sorusu; "evet" adresi açar', () {
      fakeAsync((async) {
        final h = Harness(); // routePlanner/placeSearch yok
        command(h, async, 'Kadıköy iskelesine götür');
        expect(h.tts.spoken, ['Kadıköy iskelesi için harita uygulamasını açayım mı?']);

        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.opened.single.toString(),
            'https://www.google.com/maps/dir/?api=1&destination=Kad%C4%B1k%C3%B6y+iskelesi&travelmode=walking');
        expect(h.tts.spoken.last, startsWith('Kadıköy iskelesi için yürüyüş yönlendirmesi başladı'));
        expect(h.app.navigation.active, isFalse);
        h.dispose();
      });
    });

    test('harita uygulaması açılamazsa hata söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        command(h, async, 'Kadıköy iskelesine götür');
        // Harness'in openUrl'i hep true; başarısızlık AppState dışında sınanıyor
        // (navigation_backend testi). Burada yalnızca akışın bittiği doğrulanır.
        answer(h, async, 'hayır');
        h.speakAll(async);
        expect(h.opened, isEmpty);
        h.dispose();
      });
    });

    test('konum izni yok + uygulama ön planda değil: sormaz, nedenini söyler, haritaya düşer', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        h.locationAccess.granted = false;
        h.appVisible = false;

        command(h, async, 'Taksim meydanına götür');
        expect(h.tts.spoken.last,
            'Konum izni yok, uygulamayı açıp konum iznini verin. Taksim meydanı için harita uygulamasını açayım mı?');
        expect(h.locationAccess.requests, 0, reason: 'ekran kapalıyken izin penceresi görünmez');
        expect(places.calls, isEmpty);
        expect(planner.calls, isEmpty);

        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.opened.single.queryParameters['destination'], 'Taksim meydanı');
        expect(h.app.navigation.active, isFalse);
        h.dispose();
      });
    });

    test('konum izni yok + ön planda: açıklamayla istenir; reddedilirse haritaya düşer', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        h.locationAccess
          ..granted = false
          ..grantOnRequest = false;

        command(h, async, 'Taksim meydanına götür');
        expect(h.locationAccess.requests, 1);
        expect(h.tts.spoken.last, startsWith('Konum izni verilmedi. Taksim meydanı için harita'));
        h.dispose();
      });
    });

    test('konum izni yok + ön planda + verilirse gerçek modla devam eder', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        h.locationAccess.granted = false; // grantOnRequest varsayılan true
        command(h, async, 'Kadıköy iskelesine götür');
        expect(h.locationAccess.requests, 1);
        expect(h.tts.spoken.last, contains('Başlayayım mı?'));
        h.dispose();
      });
    });

    test('telefonun konum servisi kapalı', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        h.location.serviceEnabled = false;
        command(h, async, 'Taksim meydanına götür');
        expect(h.tts.spoken.last,
            'Telefonun konum servisi kapalı. Taksim meydanı için harita uygulamasını açayım mı?');
        h.dispose();
      });
    });

    test('anlık konum alınamadı', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness(haveFix: false);
        command(h, async, 'Taksim meydanına götür');
        expect(h.tts.spoken.last,
            'Konumunuz alınamadı. Taksim meydanı için harita uygulamasını açayım mı?');
        h.dispose();
      });
    });

    test('yer araması başarısız: nedeni söyler, söylenen adla haritaya düşer', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        places.fail = true;
        command(h, async, 'Taksim meydanına götür');
        expect(h.tts.spoken.last,
            'Yer araması yapılamadı. Taksim meydanı için harita uygulamasını açayım mı?');
        h.dispose();
      });
    });

    test('rota hesaplanamadı: bulunan yerin koordinatıyla haritaya düşer', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        planner.fail = true;
        command(h, async, 'Kadıköy iskelesine götür');
        expect(h.tts.spoken.last,
            'Rota hesaplanamadı. Kadıköy İskelesi için harita uygulamasını açayım mı?');

        answer(h, async, 'evet');
        h.speakAll(async);
        final destination = h.opened.single.queryParameters['destination']!;
        final parts = destination.split(',').map(double.parse).toList();
        expect(parts[0], closeTo(enu(170, 300).lat, 1e-9));
        expect(parts[1], closeTo(enu(170, 300).lng, 1e-9));
        h.dispose();
      });
    });

    test('onaydan sonra izin geri alınırsa (başlatma anında) haritaya düşer ve nedeni söyler', () {
      fakeAsync((async) {
        final (:h, :planner, :places) = realHarness();
        command(h, async, 'Kadıköy iskelesine götür');
        expect(h.tts.spoken.last, contains('Başlayayım mı?'));

        h.locationAccess.granted = false;
        h.appVisible = false;
        answer(h, async, 'evet');
        h.speakAll(async);

        expect(h.app.navigation.active, isFalse);
        expect(h.opened, hasLength(1));
        expect(h.tts.spoken.last,
            startsWith('Konum izni yok, uygulamayı açıp konum iznini verin. Kadıköy İskelesi için yürüyüş'));
        h.dispose();
      });
    });
  });
}
