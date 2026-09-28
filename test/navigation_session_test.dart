import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/accessibility/feedback_hub.dart';
import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/navigation_session.dart';
import 'package:patika_app/navigation/route.dart';
import 'package:patika_app/permissions/location_access.dart';
import 'package:patika_app/platform/location_service.dart';
import 'package:patika_app/settings/settings.dart';

import 'fakes.dart';
import 'navigation_fixtures.dart';

class Rig {
  final FakeAsync async;
  final tts = FakeSpeechOutput();
  late final DateTime Function() now;
  late final FeedbackHub hub;
  late final SimulatedLocationService location;
  late final NavigationSession session;
  final FakePlanner? planner;

  Rig(
    this.async, {
    this.planner,
    LocationAccess? access,
    bool visible = true,
    GuidanceConfig config = const GuidanceConfig(directionCheck: false),
  }) {
    final t0 = DateTime(2026, 9, 28, 12);
    now = () => t0.add(async.elapsed);
    hub = FeedbackHub(
      queue: AnnouncementQueue(tts, now: now),
      haptics: FakeHaptics(),
      earcons: FakeEarcons(),
      settings: () => const Settings(),
    );
    location = SimulatedLocationService(now: now);
    session = NavigationSession(
      feedback: hub,
      location: location,
      planner: planner,
      access: access,
      isAppVisible: () => visible,
      now: now,
      config: config,
    );
  }

  /// Sıradaki tüm duyuruları "konuşulmuş" sayar.
  void settle() {
    for (var i = 0; i < 30; i++) {
      async.flushMicrotasks();
      tts.finishCurrent();
    }
    async.flushMicrotasks();
  }

  NavigationStart? startNow(WalkingRoute route, {PatikaLocationService? location}) {
    NavigationStart? result;
    session.start(route, location: location).then((r) => result = r);
    async.flushMicrotasks();
    return result;
  }

  /// Yürür: her nokta bir okuma, aralarında 1 sn.
  void walkTo(List<(double, double)> path, {double accuracy = 5}) {
    for (final (x, y) in path) {
      location.emit(enu(x, y), accuracy: accuracy);
      async.elapse(const Duration(seconds: 1));
      settle();
    }
  }
}

void main() {
  const toTurn = [(0.0, 0.0), (0.0, 200.0)];

  group('başlatma ve izin (melez akış)', () {
    test('izin verilmişse başlar; konum kaynağı çalışır, oturum kendisi konuşmaz', () {
      fakeAsync((async) {
        final rig = Rig(async, access: FakeLocationAccess(granted: true));
        expect(rig.startNow(testRoute()), NavigationStart.started);
        expect(rig.session.active, isTrue);
        expect(rig.location.isRunning, isTrue);
        rig.settle();
        expect(rig.tts.spoken, isEmpty);
      });
    });

    test('izin yok + uygulama ön planda: açıklamayla istenir, verilirse başlar', () {
      fakeAsync((async) {
        final access = FakeLocationAccess(granted: false, grantOnRequest: true);
        final rig = Rig(async, access: access, visible: true);
        expect(rig.startNow(testRoute()), NavigationStart.started);
        expect(access.requests, 1);
      });
    });

    test('izin yok + ön planda + reddedildi: başlamaz', () {
      fakeAsync((async) {
        final access = FakeLocationAccess(granted: false, grantOnRequest: false);
        final rig = Rig(async, access: access, visible: true);
        expect(rig.startNow(testRoute()), NavigationStart.permissionDenied);
        expect(rig.session.active, isFalse);
        expect(rig.location.isRunning, isFalse);
      });
    });

    test('izin yok + uygulama ön planda DEĞİL (ekran kapalı, sesle): sormaz, yedeğe bırakır', () {
      fakeAsync((async) {
        final access = FakeLocationAccess(granted: false);
        final rig = Rig(async, access: access, visible: false);
        expect(rig.startNow(testRoute()), NavigationStart.permissionNeeded);
        expect(access.requests, 0);
        expect(rig.session.active, isFalse);
      });
    });

    test('telefonun konum servisi kapalıysa başlamaz', () {
      fakeAsync((async) {
        final rig = Rig(async, access: FakeLocationAccess(granted: true));
        rig.location.serviceEnabled = false;
        expect(rig.startNow(testRoute()), NavigationStart.locationOff);
        expect(rig.session.active, isFalse);
      });
    });

    test('simülasyon kaynağı verilirse gerçek konum izni aranmaz', () {
      fakeAsync((async) {
        final access = FakeLocationAccess(granted: false);
        final rig = Rig(async, access: access, visible: false);
        final sim = SimulatedLocationService(now: rig.now);
        expect(rig.startNow(testRoute(), location: sim), NavigationStart.started);
        expect(access.requests, 0);
        expect(sim.isRunning, isTrue);
      });
    });
  });

  group('duyurular', () {
    test('konum akışı bilgi kipinde duyuruya dönüşür', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        rig.walkTo([(0.0, 0.0), (0.0, 100.0), (0.0, 150.0), (0.0, 190.0)]);

        expect(rig.tts.spoken, hasLength(2));
        expect(rig.tts.spoken.first, contains('sonra rota sağa sapıyor, Bağdat Caddesi'));
        expect(rig.tts.spoken.first, startsWith('50 metre'));
        expect(rig.tts.spoken.last, startsWith('10 metre'));
      });
    });

    test('"ne kadar kaldı" metni; navigasyon yokken null', () {
      fakeAsync((async) {
        final rig = Rig(async);
        expect(rig.session.remainingText(), isNull);
        rig.startNow(testRoute());
        expect(rig.session.remainingText(), 'Hedefe 450 metre, yaklaşık 6 dakika kaldı');
      });
    });

    test('konum servisi sorunu bildirilir', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        rig.location.reportIssue(LocationIssue.serviceDisabled);
        rig.settle();
        expect(rig.tts.spoken, ['Telefonun konum servisi kapalı']);
      });
    });

    test('varışta "hedef çevresindesiniz" denir, oturum ve konum kaynağı kapanır', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        rig.walkTo([
          (0.0, 0.0), (0.0, 200.0), (150.0, 200.0), (170.0, 200.0), (170.0, 230.0),
          (170.0, 260.0), (170.0, 290.0),
        ]);
        rig.settle();
        expect(rig.tts.spoken.last, 'Hedef çevresindesiniz');
        expect(rig.session.active, isFalse);
        expect(rig.location.isRunning, isFalse);
      });
    });
  });

  group('karşıya geçiş', () {
    void toCrossing(Rig rig) => rig.walkTo([
          (0.0, 0.0), (0.0, 200.0), (100.0, 200.0), (130.0, 200.0), (140.0, 200.0),
        ]);

    test('geçiş noktasında susar; "geçtim" (resumeFromCrossing) devam ettirir', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        toCrossing(rig);
        expect(rig.session.isPausedForCrossing, isTrue);
        expect(rig.tts.spoken.any((s) => s.startsWith('Karşıya geçiş noktası. Navigasyon duraklatıldı')), isTrue);

        final before = rig.tts.spoken.length;
        // Rotadan uzakta gezinmek bile hiçbir şey söyletmez.
        rig.walkTo([(-60.0, 210.0), (-60.0, 212.0), (-60.0, 214.0)]);
        expect(rig.tts.spoken.length, before);

        expect(rig.session.resumeFromCrossing(), isTrue);
        rig.settle();
        expect(rig.tts.spoken, contains('Navigasyon devam ediyor'));
        expect(rig.session.isPausedForCrossing, isFalse);
      });
    });

    test('duraklama yokken resumeFromCrossing false döner', () {
      fakeAsync((async) {
        final rig = Rig(async);
        expect(rig.session.resumeFromCrossing(), isFalse);
        rig.startNow(testRoute());
        expect(rig.session.resumeFromCrossing(), isFalse);
      });
    });

    test('90 sn içinde hiçbir kanaldan devam edilmezse zaman aşımıyla devam eder', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        toCrossing(rig);
        expect(rig.session.isPausedForCrossing, isTrue);

        async.elapse(const Duration(seconds: 80));
        rig.settle();
        expect(rig.session.isPausedForCrossing, isTrue);

        async.elapse(const Duration(seconds: 15));
        rig.settle();
        expect(rig.session.isPausedForCrossing, isFalse);
        expect(rig.tts.spoken, contains('Süre doldu, navigasyon devam ediyor'));
      });
    });

    test('Kavşak Geçiş Asistanı için elle duraklatma', () {
      fakeAsync((async) {
        final rig = Rig(async);
        expect(rig.session.pauseForCrossing(), isFalse); // açık navigasyon yok
        rig.startNow(testRoute());
        expect(rig.session.pauseForCrossing(), isTrue);
        rig.walkTo(toTurn);
        expect(rig.tts.spoken, isEmpty);
        expect(rig.session.resumeFromCrossing(), isTrue);
      });
    });
  });

  group('rota dışı ve yeniden rota', () {
    final fresh = WalkingRoute(
      destinationName: 'Kadıköy İskelesi',
      duration: const Duration(minutes: 3),
      steps: [
        RouteStep(
          maneuver: Maneuver.straight,
          streetName: 'Yeni Sokak',
          points: [enu(60, 100), enu(60, 200)],
        ),
      ],
    );

    void goOffRoute(Rig rig) =>
        rig.walkTo([(0.0, 0.0), (0.0, 100.0), (60.0, 100.0), (60.0, 100.0), (60.0, 100.0)]);

    test('planlayıcı yoksa yalnızca "rotanın dışındasınız" denir', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        goOffRoute(rig);
        expect(rig.tts.spoken, ['Rotanın dışındasınız']);
      });
    });

    test('planlayıcı varsa: bildirir, hesaplar, yeni rotayı özetler ve ona geçer', () {
      fakeAsync((async) {
        final planner = FakePlanner()..result = fresh;
        final rig = Rig(async, planner: planner);
        rig.startNow(testRoute());
        goOffRoute(rig);

        expect(rig.tts.spoken.take(2), ['Rotanın dışındasınız', 'Yeni rota hesaplanıyor']);
        expect(rig.tts.spoken.last, startsWith('Yeni rota. Kadıköy İskelesi,'));
        expect(planner.calls, hasLength(1));
        expect(planner.calls.single.name, 'Kadıköy İskelesi');
        expect(planner.calls.single.to, testRoute().end);
        expect(rig.session.route!.steps.single.streetName, 'Yeni Sokak');
        expect(rig.session.isOffRoute, isFalse);
      });
    });

    test('hesaplanamazsa söyler; 30 sn dolmadan tekrar denemez, dolunca dener', () {
      fakeAsync((async) {
        final planner = FakePlanner()..fail = true;
        final rig = Rig(async, planner: planner);
        rig.startNow(testRoute());
        goOffRoute(rig);
        expect(planner.calls, hasLength(1));
        expect(rig.tts.spoken, contains('Yeni rota hesaplanamadı'));

        // Hâlâ rota dışında, konum okumaları sürüyor.
        for (var i = 0; i < 20; i++) {
          rig.location.emit(enu(60, 100));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(planner.calls, hasLength(1)); // ~20 sn geçti

        for (var i = 0; i < 12; i++) {
          rig.location.emit(enu(60, 100));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(planner.calls, hasLength(2));

        // Bu sefer başarılı olsun: yeni rotaya geçilir.
        planner
          ..fail = false
          ..result = fresh;
        for (var i = 0; i < 31; i++) {
          rig.location.emit(enu(60, 100));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(planner.calls, hasLength(3));
        expect(rig.session.route!.steps.single.streetName, 'Yeni Sokak');
      });
    });

    test('yeni rotaya geçtikten sonra tekrar rota dışına çıkılırsa yeniden hesaplanır', () {
      fakeAsync((async) {
        final planner = FakePlanner()..result = fresh;
        final rig = Rig(async, planner: planner);
        rig.startNow(testRoute());
        goOffRoute(rig);
        expect(planner.calls, hasLength(1));

        // Yeni rota (60,100)->(60,200). Ondan da uzaklaş, 30 sn geçsin.
        async.elapse(const Duration(seconds: 31));
        for (var i = 0; i < 4; i++) {
          rig.location.emit(enu(200, 150));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(planner.calls, hasLength(2));
      });
    });
  });

  group('yön teyidi', () {
    test('yön teyidi açıkken rota yönünde yürüyünce "Rota yönündesiniz" denir', () {
      fakeAsync((async) {
        final rig = Rig(async, config: const GuidanceConfig());
        expect(rig.session.announcesDirection, isTrue);
        rig.startNow(testRoute());
        // 1,4 m/sn, saniyede bir okuma, kuzeye (rota yönü).
        for (var i = 0; i < 20; i++) {
          rig.location.emit(enu(0, 1.4 * i));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(rig.tts.spoken, ['Rota yönündesiniz']);
      });
    });

    test('rotanın tersine yürüyünce "Rotanın tersi yönündesiniz" denir', () {
      fakeAsync((async) {
        final rig = Rig(async, config: const GuidanceConfig());
        rig.startNow(testRoute());
        for (var i = 0; i < 15; i++) {
          rig.location.emit(enu(0, -1.4 * i));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(rig.tts.spoken, ['Rotanın tersi yönündesiniz']);
      });
    });

    test('kapalıyken (bayrak) hiçbir şey söylemez ve özet notu istemez', () {
      fakeAsync((async) {
        final rig = Rig(async); // varsayılan test yapılandırması: directionCheck false
        expect(rig.session.announcesDirection, isFalse);
        rig.startNow(testRoute());
        for (var i = 0; i < 20; i++) {
          rig.location.emit(enu(0, 1.4 * i));
          async.elapse(const Duration(seconds: 1));
          rig.settle();
        }
        expect(rig.tts.spoken, isEmpty);
      });
    });
  });

  group('konum sağlığı ve kapatma', () {
    test('15 sn hiç okuma gelmezse ticker "konum belirsiz" der', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        async.elapse(const Duration(seconds: 16));
        rig.settle();
        expect(rig.tts.spoken, ['Konum belirsiz']);
        expect(rig.session.isGpsWeak, isTrue);
      });
    });

    test('stop: konum kaynağı kapanır, ticker durur, sonra hiç duyuru gelmez', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.startNow(testRoute());
        var stopped = false;
        rig.session.stop().then((v) => stopped = v);
        async.flushMicrotasks();

        expect(stopped, isTrue);
        expect(rig.session.active, isFalse);
        expect(rig.location.isRunning, isFalse);

        async.elapse(const Duration(seconds: 60));
        rig.settle();
        expect(rig.tts.spoken, isEmpty); // ticker "konum belirsiz" demedi
      });
    });

    test('çalışan yokken stop false döner', () {
      fakeAsync((async) {
        final rig = Rig(async);
        var result = true;
        rig.session.stop().then((v) => result = v);
        async.flushMicrotasks();
        expect(result, isFalse);
      });
    });
  });
}
