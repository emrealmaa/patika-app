import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/route.dart';

import 'navigation_fixtures.dart';

// Deneme rotası: 0,0 -> 0,200 (sağa dön) -> 150,200 -> karşıya geçiş (20 m)
// -> 170,200 (sola dön) -> 170,300 hedef. Ayrıntı: navigation_fixtures.dart
const _toTurn = [(0.0, 0.0), (0.0, 200.0)];
const _toCrossing = [(0.0, 0.0), (0.0, 200.0), (150.0, 200.0)];
const _wholeRoute = [
  (0.0, 0.0),
  (0.0, 200.0),
  (150.0, 200.0),
  (170.0, 200.0),
  (170.0, 300.0),
];

// Yön teyidi ayrı bir test grubunda (aşağıda); diğer senaryolar odaklı kalsın diye kapalı.
GuidanceEngine engine({WalkingRoute? route, DateTime? startedAt}) => GuidanceEngine(
      route ?? testRoute(),
      config: const GuidanceConfig(directionCheck: false),
      startedAt: startedAt,
    );

void main() {
  group('dönüş duyuruları', () {
    test('dönüşe yaklaşırken iki kez söylenir: uzak (≤50 m) ve yakın (≤15 m)', () {
      final events = walk(engine(), walkPath(_toTurn)).whereType<ManeuverAhead>().toList();

      expect(events, hasLength(2));
      expect(events.first.meters, inInclusiveRange(35, 50.5));
      expect(events.last.meters, inInclusiveRange(5, 15.5));
      for (final e in events) {
        expect(e.maneuver, Maneuver.right);
        expect(e.streetName, 'Bağdat Caddesi');
      }
    });

    test('dönüş geçildikten sonra tekrar söylenmez, geri sapıtan konum da tekrar ettirmez', () {
      final e = engine();
      walk(e, walkPath(_toTurn));
      final after = walk(e, [(0.0, 190.0), (0.0, 195.0), (5.0, 200.0), (20.0, 200.0), (10.0, 200.0)]);
      expect(after.whereType<ManeuverAhead>(), isEmpty);
    });

    test('doğrudan yakın bölgeye düşen ilk okuma yalnızca yakın duyuruyu verir', () {
      final events = engine().update(fixAt(0, 188));
      expect(events, hasLength(1));
      expect((events.single as ManeuverAhead).meters, closeTo(12, 0.5));
    });

    test('düz devam adımı sessizdir (bilişsel yük)', () {
      final straightRoute = WalkingRoute(
        destinationName: 'Yer',
        duration: const Duration(minutes: 3),
        steps: [
          RouteStep(maneuver: Maneuver.straight, points: [enu(0, 0), enu(0, 100)]),
          RouteStep(maneuver: Maneuver.straight, points: [enu(0, 100), enu(0, 300)]),
        ],
      );
      final events = walk(engine(route: straightRoute), walkPath([(0, 0), (0, 200)]));
      expect(events.whereType<ManeuverAhead>(), isEmpty);
    });

    test('konum doğruluğu iyiyken tek okumalık sıçrama ilerlemeyi geri almaz', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 120)]));
      final before = e.remainingMeters;
      e.update(fixAt(0, 100, seconds: 50));
      expect(e.remainingMeters, closeTo(before, 0.5));
    });
  });

  group('karşıya geçiş: navigasyon karar vermez, susar', () {
    test('geçiş noktası yaklaşınca haber verir, varınca duraklar', () {
      final events = walk(engine(), walkPath(_toCrossing));
      expect(events.whereType<CrossingAhead>(), hasLength(1));
      expect(events.whereType<CrossingPoint>(), hasLength(1));
      expect(events.whereType<CrossingAhead>().single.meters, lessThanOrEqualTo(50.5));
    });

    test('duraklamadayken hiçbir olay üretmez, rotadan uzak konumda bile', () {
      final e = engine();
      walk(e, walkPath(_toCrossing));
      expect(e.isPausedForCrossing, isTrue);

      // Kullanıcı Google'ın çizdiği çizgiden 60 m uzakta (rotanın hiçbir
      // parçasına yakın değil) karşıya geçiyor: "rotanın dışındasınız"
      // denmemeli.
      final events = [
        for (var i = 0; i < 6; i++) ...e.update(fixAt(-60, 210, seconds: 100 + i)),
      ];
      expect(events, isEmpty);
      expect(e.isOffRoute, isFalse);
      expect(e.isPausedForCrossing, isTrue);
    });

    test('"geçtim": devam eder ve geçişin ardındaki dönüşü hemen duyurur', () {
      final e = engine();
      walk(e, walkPath(_toCrossing));

      final events = e.resumeFromCrossing();
      expect(events.first, isA<CrossingResumed>());
      final turn = events.whereType<ManeuverAhead>().single;
      expect(turn.maneuver, Maneuver.left);
      expect(turn.streetName, 'İskele Sokağı');
      expect(turn.meters, lessThan(5));
      expect(e.isPausedForCrossing, isFalse);

      // Aynı dönüş bir daha söylenmez.
      expect(walk(e, [(170.0, 203.0), (170.0, 210.0)]).whereType<ManeuverAhead>(), isEmpty);
    });

    test('konum geçişin 25 m ötesine ilerlerse kendiliğinden devam eder', () {
      final e = engine();
      final events = walk(e, walkPath(_wholeRoute));
      expect(events.whereType<CrossingResumed>(), hasLength(1));
      expect(e.isPausedForCrossing, isFalse);
    });

    test('duraklama yokken resumeFromCrossing hiçbir şey yapmaz', () {
      expect(engine().resumeFromCrossing(), isEmpty);
    });

    test('geçiş adımı GPS boşluğunda atlanırsa kimse duraklatılmaz', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 200), (100, 200)]));
      // Bir anda geçişin çok ötesi.
      final events = e.update(fixAt(170, 240, seconds: 200));
      expect(events.whereType<CrossingPoint>(), isEmpty);
      expect(e.isPausedForCrossing, isFalse);
    });
  });

  group('duraklama üst süresi (90 sn) ve elle duraklatma', () {
    /// Geçiş noktasında duraklamış motor ve duraklamanın başladığı saniye.
    ({GuidanceEngine e, int t}) pausedEngine() {
      final e = engine();
      final path = walkPath(_toCrossing);
      for (var i = 0; i < path.length; i++) {
        final events = e.update(fixAt(path[i].$1, path[i].$2, seconds: i));
        if (events.any((x) => x is CrossingPoint)) return (e: e, t: i);
      }
      fail('geçiş noktası hiç tetiklenmedi');
    }

    test('okuma gelmese de tick: 89. sn hâlâ duraklı, 90. sn devam eder', () {
      final (:e, :t) = pausedEngine();
      expect(e.tick(at(t + 89)), isEmpty);
      expect(e.isPausedForCrossing, isTrue);

      final events = e.tick(at(t + 90));
      expect(events.first, isA<CrossingTimedOut>());
      expect(e.isPausedForCrossing, isFalse);
    });

    test('zaman aşımı ilerlemeyi zıplatmaz: kullanıcı geçişin öncesinde olabilir', () {
      final (:e, :t) = pausedEngine();
      final before = e.remainingMeters;
      final events = e.tick(at(t + 90));

      expect(e.remainingMeters, closeTo(before, 1));
      // Geçişin ardındaki dönüş, gerçek uzaklığıyla duyurulur.
      final turn = events.whereType<ManeuverAhead>().single;
      expect(turn.maneuver, Maneuver.left);
      expect(turn.meters, greaterThan(15));
    });

    test('konum okuması gelirken de zaman aşımı işler (kötü doğrulukta bile)', () {
      final (:e, :t) = pausedEngine();
      final events = e.update(fixAt(-60, 210, accuracy: 80, seconds: t + 91));
      expect(events.first, isA<CrossingTimedOut>());
      expect(e.isPausedForCrossing, isFalse);
    });

    test('zaman aşımından sonra aynı geçiş bir daha duraklatmaz', () {
      final (:e, :t) = pausedEngine();
      e.tick(at(t + 90));
      final events = walk(e, [(150.0, 200.0), (160.0, 200.0), (170.0, 200.0)]);
      expect(events.whereType<CrossingPoint>(), isEmpty);
      expect(e.isPausedForCrossing, isFalse);
    });

    test('elle duraklatma: hiçbir olay yok, konumla kendiliğinden devam etmez', () {
      final e = engine();
      e.pauseForCrossing(at(0));
      expect(e.isPausedForCrossing, isTrue);

      // Rota boyunca ilerlemek (normalde dönüş duyuruları gelirdi) susar.
      final events = walk(e, walkPath([(0, 0), (0, 190)]));
      expect(events, isEmpty);
      expect(e.isPausedForCrossing, isTrue);

      // Geçişin çok ötesine geçilse bile: adım yok, konumla devam yok.
      expect(walk(e, [(170.0, 260.0)]), isEmpty);
      expect(e.isPausedForCrossing, isTrue);
    });

    test('elle duraklatma "geçtim" ile biter ve o anki dönüşü duyurur', () {
      final e = engine();
      e.pauseForCrossing(at(0));
      walk(e, walkPath([(0, 0), (0, 190)]));

      final events = e.resumeFromCrossing();
      expect(events.first, isA<CrossingResumed>());
      expect(events.whereType<ManeuverAhead>().single.maneuver, Maneuver.right);
    });

    test('elle duraklatma da 90 sn ile biter; tekrar duraklatmak süreyi yenilemez', () {
      final e = engine();
      e.pauseForCrossing(at(0));
      e.pauseForCrossing(at(60)); // yok sayılır
      expect(e.tick(at(89)), isEmpty);
      expect(e.tick(at(90)).first, isA<CrossingTimedOut>());
    });

    test('dört kanal birbirinden bağımsız: her biri tek başına duraklamayı bitirir', () {
      // 1) konum
      final byLocation = engine();
      final events = walk(byLocation, walkPath(_wholeRoute));
      expect(events.whereType<CrossingResumed>(), hasLength(1));
      // 2) gözlük çift dokunuşu ve 3) "geçtim": ikisi de resumeFromCrossing
      final byUser = pausedEngine().e;
      expect(byUser.resumeFromCrossing().first, isA<CrossingResumed>());
      // 4) zaman aşımı
      final p = pausedEngine();
      expect(p.e.tick(at(p.t + 90)).first, isA<CrossingTimedOut>());
    });

    test('süre GuidanceConfig\'den ayarlanır', () {
      final e = GuidanceEngine(
        testRoute(),
        config: const GuidanceConfig(crossingMaxPause: Duration(seconds: 30)),
      );
      e.pauseForCrossing(at(0));
      expect(e.tick(at(29)), isEmpty);
      expect(e.tick(at(30)).first, isA<CrossingTimedOut>());
    });
  });

  group('varış', () {
    test('tüm rota: sıralı olaylar, sonunda "hedef çevresindesiniz" ve motor biter', () {
      final e = engine();
      final events = walk(e, walkPath(_wholeRoute));

      expect(events.map((x) => x.runtimeType).toList(), [
        ManeuverAhead,
        ManeuverAhead,
        CrossingAhead,
        CrossingPoint,
        CrossingResumed,
        NearDestination,
        Arrived,
      ]);
      expect(e.isFinished, isTrue);
      expect(e.update(fixAt(170, 300, seconds: 500)), isEmpty);
    });
  });

  group('rota dışı', () {
    // Düz kuzey adımında (0,100) çevresi; doğruluk 5 -> eşik 25 m.
    test('ardışık 3 okuma eşiği aşarsa bir kez "rota dışı" denir', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      expect(e.update(fixAt(60, 100, seconds: 20)), isEmpty);
      expect(e.update(fixAt(60, 100, seconds: 21)), isEmpty);
      expect(e.update(fixAt(60, 100, seconds: 22)).single, isA<OffRoute>());
      expect(e.isOffRoute, isTrue);
      expect(e.update(fixAt(60, 100, seconds: 23)), isEmpty);
    });

    test('tek/iki kötü okuma sayacı, arada iyi okuma da sıfırlar', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      e.update(fixAt(60, 100, seconds: 20));
      e.update(fixAt(60, 100, seconds: 21));
      e.update(fixAt(0, 105, seconds: 22)); // rotada
      e.update(fixAt(60, 105, seconds: 23));
      e.update(fixAt(60, 105, seconds: 24));
      expect(e.isOffRoute, isFalse);
    });

    test('geri dönüş eşiği daha dar (histerezis): 18 m hâlâ dışarıda, 8 m rotada', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      for (var i = 0; i < 3; i++) {
        e.update(fixAt(60, 100, seconds: 20 + i));
      }
      expect(e.isOffRoute, isTrue);

      expect(e.update(fixAt(18, 100, seconds: 30)), isEmpty);
      expect(e.isOffRoute, isTrue);
      expect(e.update(fixAt(8, 100, seconds: 31)).single, isA<BackOnRoute>());
      expect(e.isOffRoute, isFalse);
    });

    test('kötü doğruluk eşiği gevşetir: doğruluk 30 iken 40 m sapma rota dışı sayılmaz', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      for (var i = 0; i < 5; i++) {
        e.update(fixAt(40, 100, accuracy: 30, seconds: 20 + i));
      }
      expect(e.isOffRoute, isFalse);
    });
  });

  group('GPS sağlığı', () {
    test('3 kötü okuma -> "konum belirsiz" (bir kez); o okumalarla konum yargısı verilmez', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      final all = [
        for (var i = 0; i < 6; i++) ...e.update(fixAt(500, 500, accuracy: 60, seconds: 20 + i)),
      ];
      expect(all.single, isA<GpsWeak>());
      expect(e.isGpsWeak, isTrue);
      expect(e.isOffRoute, isFalse); // uzak ama güvenilmez okuma "rota dışı" yapmaz
    });

    test('doğruluk 30 m altına inince toparlanır; 35 m arada sessiz kalır', () {
      final e = engine();
      walk(e, walkPath([(0, 0), (0, 100)]));
      for (var i = 0; i < 3; i++) {
        e.update(fixAt(0, 100, accuracy: 60, seconds: 20 + i));
      }
      expect(e.update(fixAt(0, 100, accuracy: 35, seconds: 30)), isEmpty);
      expect(e.isGpsWeak, isTrue);
      expect(e.update(fixAt(0, 100, accuracy: 20, seconds: 31)).single, isA<GpsRecovered>());
      expect(e.isGpsWeak, isFalse);
    });

    test('15 sn hiç okuma gelmezse tick "konum belirsiz" der', () {
      final e = engine(startedAt: at(0));
      e.update(fixAt(0, 10, seconds: 1));
      expect(e.tick(at(10)), isEmpty);
      expect(e.tick(at(17)).single, isA<GpsWeak>());
      expect(e.tick(at(40)), isEmpty); // bir kez
      expect(e.update(fixAt(0, 12, accuracy: 10, seconds: 41)).single, isA<GpsRecovered>());
    });

    test('hiç okuma gelmeden de (startedAt ile) zaman aşımı çalışır', () {
      expect(engine(startedAt: at(0)).tick(at(20)).single, isA<GpsWeak>());
      expect(engine().tick(at(20)), isEmpty); // başlangıç zamanı yoksa yargı yok
    });

    test('duraklamadayken tick "konum belirsiz" demez (90 sn dolunca zaman aşımı gelir)', () {
      final e = engine(startedAt: at(0));
      walk(e, walkPath(_toCrossing));
      expect(e.isPausedForCrossing, isTrue);
      // Son okumadan >15 sn geçti ama duraklıyoruz: konum belirsiz denmez.
      expect(e.tick(at(60)), isEmpty);
      // 90 sn dolunca "konum belirsiz" değil, zaman aşımı gelir.
      expect(e.tick(at(500)).first, isA<CrossingTimedOut>());
    });
  });

  group('kalan yol / süre', () {
    test('başlangıçta toplam, ortada orantılı', () {
      final e = engine();
      expect(e.remainingMeters, closeTo(470, 0.5));
      expect(e.remainingDuration, const Duration(minutes: 6));

      walk(e, walkPath([(0, 0), (0, 200), (100, 200)])); // 300. metre
      expect(e.remainingMeters, closeTo(170, 1));
      expect(e.remainingDuration.inSeconds, closeTo(6 * 60 * 170 / 470, 3));
    });
  });

  group('yön teyidi (hareket yönünden)', () {
    GuidanceEngine dirEngine({WalkingRoute? route, GuidanceConfig config = const GuidanceConfig()}) =>
        GuidanceEngine(route ?? testRoute(), config: config);

    /// (0,0)'dan (dx,dy) yönünde [speed] m/sn ile yürür; her saniye bir okuma.
    /// [from]..[to) saniye aralığı (pozisyon = hız x saniye).
    List<GuidanceEvent> stride(
      GuidanceEngine e, {
      double dx = 0,
      double dy = 1,
      double speed = 1.4,
      int from = 0,
      int to = 30,
      double accuracy = 5,
    }) =>
        [
          for (var i = from; i < to; i++)
            ...e.update(fixAt(dx * speed * i, dy * speed * i, accuracy: accuracy, seconds: i)),
        ];

    List<DirectionInfo> infos(List<GuidanceEvent> events) => events.whereType<DirectionInfo>().toList();

    test('rota yönünde yürüyünce bir kez "rota yönünde" denir, tekrar etmez', () {
      final result = infos(stride(dirEngine(), to: 40));
      expect(result.map((i) => i.verdict), [DirectionVerdict.along]);
    });

    test('rotanın tersine yürüyünce "tersi" denir (rota dışı uyarısından önce)', () {
      final events = stride(dirEngine(), dy: -1, to: 40);
      final first = events.first;
      expect(first, isA<DirectionInfo>());
      expect((first as DirectionInfo).verdict, DirectionVerdict.opposite);
      final offRouteAt = events.indexWhere((e) => e is OffRoute);
      expect(offRouteAt, isNot(-1));
      expect(offRouteAt, greaterThan(0), reason: 'yön bilgisi rota dışı uyarısından önce gelmeli');
    });

    test('rotaya yan yürüyünce "yan" denir', () {
      final result = infos(stride(dirEngine(), dx: 1, dy: 0, to: 40));
      expect(result.first.verdict, DirectionVerdict.across);
    });

    test('ters yürüyüp geri dönünce düzeldiği söylenir: tersi, sonra rota yönünde', () {
      final e = dirEngine();
      final events = [
        ...stride(e, dy: -1, to: 12), // güneye 12 sn
        for (var i = 12; i < 40; i++)
          ...e.update(fixAt(0, -1.4 * 11 + 1.4 * (i - 11), seconds: i)), // kuzeye dön
      ];
      expect(infos(events).map((i) => i.verdict),
          [DirectionVerdict.opposite, DirectionVerdict.along]);
    });

    test('yavaş yürürken (< 0,7 m/sn) hiç yön verilmez', () {
      expect(infos(stride(dirEngine(), speed: 0.3, to: 120)), isEmpty);
      expect(infos(stride(dirEngine(), speed: 0.6, to: 80)), isEmpty);
    });

    test('0,9 m/sn yürüme hızıdır: yön verilir', () {
      expect(infos(stride(dirEngine(), speed: 0.9, to: 40)).single.verdict, DirectionVerdict.along);
    });

    test('konum doğruluğu 10 m\'den kötüyse (15 m) yön verilmez', () {
      expect(infos(stride(dirEngine(), accuracy: 15, to: 60)), isEmpty);
    });

    test('gereken mesafe doğrulukla büyür: doğruluk 10 iken 20 m şart', () {
      final e = dirEngine();
      expect(infos(stride(e, accuracy: 10, to: 15)), isEmpty); // 14 sn = 19,6 m
      expect(infos(stride(e, accuracy: 10, from: 15, to: 18)), hasLength(1));
    });

    test('kapatma bayrağı: directionCheck false ise hiç konuşmaz', () {
      final e = dirEngine(config: const GuidanceConfig(directionCheck: false));
      expect(infos(stride(e, to: 60)), isEmpty);
    });

    test('rota köşe alıyorsa (pencerede iki farklı yön) yanıltıcı karar vermez', () {
      // 10 m kuzey, sonra 100 m doğu. Köşeyi içeren pencere yanlış bir yön
      // gösterir; doğru davranış: köşeden sonra düz doğuya yürüyünce "rota yönünde".
      final route = WalkingRoute(
        destinationName: 'Yer',
        duration: const Duration(minutes: 3),
        steps: [
          RouteStep(maneuver: Maneuver.straight, points: [enu(0, 0), enu(0, 10)]),
          RouteStep(maneuver: Maneuver.right, points: [enu(0, 10), enu(100, 10)]),
        ],
      );
      final e = dirEngine(route: route);
      final events = walk(e, walkPath([(0, 0), (0, 10), (100, 10)], stepMeters: 1.4));
      expect(infos(events).map((i) => i.verdict), [DirectionVerdict.along]);
    });

    test('rotanın ilk 100 metresinden sonra denenmez', () {
      final e = dirEngine();
      e.update(fixAt(0, 150, seconds: 0)); // GPS boşluğu: doğrudan 150. metre
      final events = [
        for (var i = 1; i < 40; i++) ...e.update(fixAt(0, 150 + 1.4 * i, seconds: i)),
      ];
      expect(infos(events), isEmpty);
    });
  });
}
