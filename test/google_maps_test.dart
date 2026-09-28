import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/google_client.dart';
import 'package:patika_app/navigation/google_parsing.dart';
import 'package:patika_app/navigation/maps_config.dart';
import 'package:patika_app/navigation/place_search.dart';
import 'package:patika_app/navigation/route.dart';
import 'package:patika_app/navigation/route_planner.dart';

import 'navigation_fixtures.dart';

/// Routes API örnek yanıtı (belgelenen şekilde: routes[].duration ve
/// legs[].steps[].{polyline.encodedPolyline, navigationInstruction}).
/// GERÇEK bir yanıttan kaydedilmedi; gerçek anahtarla doğrulama telefon testi
/// listesinde (CLAUDE.md).
Map<String, dynamic> routesJson({List<Map<String, dynamic>>? steps, String? duration = '360s'}) => {
      'routes': [
        {
          'duration': ?duration,
          'legs': [
            {
              'steps': steps ??
                  [
                    step([enu(0, 0), enu(0, 200)], 'DEPART', 'Kuzeye doğru yürüyün'),
                    step([enu(0, 200), enu(150, 200)], 'TURN_RIGHT', 'Sağa dönün'),
                    step([enu(150, 200), enu(170, 200)], 'STRAIGHT', 'Karşıya geçin'),
                    step([enu(170, 200), enu(170, 300)], 'TURN_LEFT', 'Sola dönün'),
                  ],
            },
          ],
        },
      ],
    };

Map<String, dynamic> step(List<LatLng> points, String maneuver, String text) => {
      'polyline': {'encodedPolyline': encodePolyline(points)},
      'navigationInstruction': {'maneuver': maneuver, 'instructions': text},
    };

void main() {
  group('polyline kodla-çöz (fixture doğrulaması)', () {
    test('gidiş-dönüş aynı noktaları verir', () {
      final points = [enu(0, 0), enu(0, 200), enu(150, 200)];
      final back = decodePolyline(encodePolyline(points));
      expect(back, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(distanceMeters(back[i], points[i]), lessThan(1.5)); // 1e-5 derece ≈ 1,1 m
      }
    });
  });

  group('splitPolyline', () {
    test('kesim noktası iki parçada da bulunur; uzunluklar toplanır', () {
      final line = [enu(0, 0), enu(0, 50)];
      final (:head, :tail) = splitPolyline(line, 20);
      expect(head, hasLength(2));
      expect(tail, hasLength(2));
      expect(head.last, tail.first);
      expect(distanceMeters(head.first, head.last), closeTo(20, 0.1));
      expect(distanceMeters(tail.first, tail.last), closeTo(30, 0.1));
    });

    test('birden çok parçalı çizgide doğru köşede bölünür', () {
      final line = [enu(0, 0), enu(0, 10), enu(30, 10)];
      final (:head, :tail) = splitPolyline(line, 25);
      expect(head, hasLength(3)); // baş, köşe, kesim
      expect(tail, hasLength(2)); // kesim, uç
    });

    test('çizgiden uzun mesafede kalan boş döner', () {
      final (:head, :tail) = splitPolyline([enu(0, 0), enu(0, 10)], 50);
      expect(tail, isEmpty);
      expect(head, hasLength(2));
    });
  });

  group('manevra çevirisi', () {
    test('dönüşler, U dönüşleri ve sessizler', () {
      expect(mapManeuver('TURN_LEFT'), Maneuver.left);
      expect(mapManeuver('TURN_SLIGHT_LEFT'), Maneuver.slightLeft);
      expect(mapManeuver('TURN_SHARP_LEFT'), Maneuver.sharpLeft);
      expect(mapManeuver('TURN_RIGHT'), Maneuver.right);
      expect(mapManeuver('TURN_SLIGHT_RIGHT'), Maneuver.slightRight);
      expect(mapManeuver('TURN_SHARP_RIGHT'), Maneuver.sharpRight);
      expect(mapManeuver('UTURN_LEFT'), Maneuver.uTurn);
      expect(mapManeuver('UTURN_RIGHT'), Maneuver.uTurn);
      for (final quiet in [null, 'MANEUVER_UNSPECIFIED', 'STRAIGHT', 'DEPART', 'NAME_CHANGE', 'MERGE']) {
        expect(mapManeuver(quiet), Maneuver.straight, reason: '$quiet');
      }
      for (final complex in ['RAMP_LEFT', 'FORK_RIGHT', 'ROUNDABOUT_LEFT', 'FERRY', 'YENİ_BİR_DEĞER']) {
        expect(mapManeuver(complex), Maneuver.other, reason: complex);
      }
    });
  });

  group('karşıya geçiş tespiti (sezgisel; metin seslendirilmez)', () {
    test('geçişten söz eden talimatlar', () {
      for (final text in [
        'Karşıya geçin',
        'Yaya geçidinden karşıya geçin',
        'YAYA GEÇİDİNDEN devam edin',
        'Karşı tarafa geçin',
        'Cross the street',
        'Use the crosswalk',
      ]) {
        expect(looksLikeCrossing(text), isTrue, reason: text);
      }
    });

    test('geçişten söz etmeyenler ve boşlar', () {
      for (final text in ['Sağa dönün', 'Bağdat Caddesi üzerinde sola dönün', 'Kuzeye doğru yürüyün', '', null]) {
        expect(looksLikeCrossing(text), isFalse, reason: '$text');
      }
    });
  });

  group('parseRoutesResponse', () {
    test('örnek yanıt: adımlar, manevralar, geçiş, süre; sokak adı yok', () {
      final route = parseRoutesResponse(routesJson(), destinationName: 'Kadıköy İskelesi');

      expect(route.destinationName, 'Kadıköy İskelesi');
      expect(route.duration, const Duration(minutes: 6));
      expect(route.steps.map((s) => s.maneuver),
          [Maneuver.straight, Maneuver.right, Maneuver.straight, Maneuver.left]);
      expect(route.steps.map((s) => s.isCrossing), [false, false, true, false]);
      expect(route.steps.every((s) => s.streetName == null), isTrue,
          reason: 'Routes API yapısal sokak adı vermiyor');
      expect(route.lengthMeters, closeTo(470, 5));
    });

    test('uzun geçiş adımı ikiye bölünür: 20 m geçiş + kalan normal yürüyüş', () {
      final route = parseRoutesResponse(
        routesJson(steps: [
          step([enu(0, 0), enu(0, 100)], 'DEPART', 'Yürüyün'),
          step([enu(0, 100), enu(80, 100)], 'TURN_RIGHT', 'Karşıya geçin'),
        ]),
        destinationName: 'Yer',
      );
      expect(route.steps, hasLength(3));
      expect(route.steps[1].isCrossing, isTrue);
      expect(route.steps[1].maneuver, Maneuver.right);
      expect(route.steps[1].lengthMeters, closeTo(20, 1.5));
      expect(route.steps[2].isCrossing, isFalse);
      expect(route.steps[2].maneuver, Maneuver.straight);
      expect(route.steps[2].lengthMeters, closeTo(60, 1.5));
    });

    test('kısa geçiş adımı bölünmez', () {
      final route = parseRoutesResponse(
        routesJson(steps: [step([enu(0, 0), enu(0, 25)], 'STRAIGHT', 'Karşıya geçin')]),
        destinationName: 'Yer',
      );
      expect(route.steps, hasLength(1));
      expect(route.steps.single.isCrossing, isTrue);
    });

    test('süre gelmezse yürüme hızından tahmin edilir (~1,25 m/sn)', () {
      final route = parseRoutesResponse(routesJson(duration: null), destinationName: 'Yer');
      expect(route.duration.inSeconds, closeTo(470 / 1.25, 5));
    });

    test('çizgisi olmayan/bozuk adım atlanır; hiç adım kalmazsa hata', () {
      final ok = parseRoutesResponse(
        routesJson(steps: [
          {'navigationInstruction': {'maneuver': 'TURN_LEFT'}},
          step([enu(0, 0), enu(0, 50)], 'DEPART', 'Yürüyün'),
        ]),
        destinationName: 'Yer',
      );
      expect(ok.steps, hasLength(1));

      expect(
        () => parseRoutesResponse(routesJson(steps: [{'polyline': {}}]), destinationName: 'Yer'),
        throwsA(isA<RoutePlanException>()),
      );
    });

    test('rota yoksa/boş yanıtta RoutePlanException', () {
      for (final json in [<String, dynamic>{}, {'routes': []}, {'routes': [42]}]) {
        expect(() => parseRoutesResponse(json, destinationName: 'Yer'), throwsA(isA<RoutePlanException>()));
      }
    });

    test('süre çözümleme', () {
      expect(parseGoogleDuration('900s'), const Duration(minutes: 15));
      expect(parseGoogleDuration('12.5s'), const Duration(milliseconds: 12500));
      expect(parseGoogleDuration('abc'), isNull);
      expect(parseGoogleDuration(null), isNull);
    });
  });

  group('parsePlacesResponse', () {
    test('adlar, adresler ve konumlar; konumsuz/adsız atlanır', () {
      final places = parsePlacesResponse({
        'places': [
          {
            'displayName': {'text': 'Kadıköy İskelesi', 'languageCode': 'tr'},
            'formattedAddress': 'Osmanağa, Kadıköy/İstanbul',
            'location': {'latitude': 40.9925, 'longitude': 29.0245},
          },
          {'displayName': {'text': 'Konumsuz'}},
          {'location': {'latitude': 1.0, 'longitude': 2.0}},
          {
            'displayName': {'text': 'Kadıköy Meydanı'},
            'location': {'latitude': 40.99, 'longitude': 29.03},
          },
        ],
      });
      expect(places.map((p) => p.name), ['Kadıköy İskelesi', 'Kadıköy Meydanı']);
      expect(places.first.address, 'Osmanağa, Kadıköy/İstanbul');
      expect(places.first.location, const LatLng(40.9925, 29.0245));
      expect(places.last.address, isNull);
    });

    test('sonuç yoksa boş liste', () {
      expect(parsePlacesResponse({}), isEmpty);
    });
  });

  group('GoogleRoutePlanner (sahte HTTP)', () {
    const key = 'TEST-ANAHTAR-123';

    test('istek: adres, başlıklar (anahtar yalnızca başlıkta), gövde', () async {
      late http.Request seen;
      final planner = GoogleRoutePlanner(
        apiKey: key,
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(routesJson()), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final route = await planner.plan(
        from: enu(0, 0),
        to: enu(170, 300),
        destinationName: 'Kadıköy İskelesi',
      );

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://routes.googleapis.com/directions/v2:computeRoutes');
      expect(seen.url.toString(), isNot(contains(key)), reason: 'anahtar adrese yazılmaz');
      expect(seen.headers['X-Goog-Api-Key'], key);
      expect(seen.headers['X-Goog-FieldMask'],
          'routes.duration,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.navigationInstruction');

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['travelMode'], 'WALK');
      expect(body['languageCode'], 'tr');
      expect(body['units'], 'METRIC');
      final origin = body['origin']['location']['latLng'] as Map;
      expect(origin['latitude'], closeTo(enu(0, 0).lat, 1e-9));
      final dest = body['destination']['location']['latLng'] as Map;
      expect(dest['longitude'], closeTo(enu(170, 300).lng, 1e-9));

      expect(route.steps, hasLength(4));
    });

    test('HTTP hatası RoutePlanException; mesajda anahtar yok', () async {
      final planner = GoogleRoutePlanner(
        apiKey: key,
        client: MockClient((_) async => http.Response('{"error":{"message":"denied $key"}}', 403)),
      );
      await expectLater(
        planner.plan(from: enu(0, 0), to: enu(1, 1), destinationName: 'Yer'),
        throwsA(isA<RoutePlanException>()
            .having((e) => e.message, 'message', 'HTTP 403')
            .having((e) => e.toString(), 'toString', isNot(contains(key)))),
      );
    });

    test('ağ hatası, bozuk yanıt ve zaman aşımı hep RoutePlanException', () async {
      Future<void> expectFails(http.Client client, {Duration? timeout}) => expectLater(
            GoogleRoutePlanner(
              apiKey: key,
              client: client,
              timeout: timeout ?? const Duration(seconds: 10),
            ).plan(from: enu(0, 0), to: enu(1, 1), destinationName: 'Yer'),
            throwsA(isA<RoutePlanException>()),
          );

      await expectFails(MockClient((_) async => throw http.ClientException('bağlantı yok')));
      await expectFails(MockClient((_) async => throw StateError('beklenmedik')));
      await expectFails(MockClient((_) async => http.Response('<html>', 200)));
      await expectFails(MockClient((_) async => http.Response('{"routes":[]}', 200)));
      await expectFails(
        MockClient((_) => Completer<http.Response>().future), // hiç yanıt vermez
        timeout: const Duration(milliseconds: 20),
      );
    });
  });

  group('GooglePlaceSearch (sahte HTTP)', () {
    const key = 'TEST-ANAHTAR-123';
    final response = jsonEncode({
      'places': [
        {
          'displayName': {'text': 'Kadıköy İskelesi'},
          'location': {'latitude': 40.9925, 'longitude': 29.0245},
        },
      ],
    });

    test('istek: metin, dil, bölge, en çok 3 sonuç, yakın konum önceliği', () async {
      late http.Request seen;
      final search = GooglePlaceSearch(
        apiKey: key,
        client: MockClient((request) async {
          seen = request;
          return http.Response(response, 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final results = await search.search('Kadıköy iskelesi', near: enu(0, 0));

      expect(seen.url.toString(), 'https://places.googleapis.com/v1/places:searchText');
      expect(seen.headers['X-Goog-Api-Key'], key);
      expect(seen.headers['X-Goog-FieldMask'], 'places.displayName,places.formattedAddress,places.location');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['textQuery'], 'Kadıköy iskelesi');
      expect(body['languageCode'], 'tr');
      expect(body['regionCode'], 'TR');
      expect(body['maxResultCount'], 3);
      final circle = body['locationBias']['circle'] as Map;
      expect(circle['radius'], 5000.0);
      expect(circle['center']['latitude'], closeTo(enu(0, 0).lat, 1e-9));

      expect(results.single.name, 'Kadıköy İskelesi');
    });

    test('konum yoksa locationBias gönderilmez', () async {
      late http.Request seen;
      final search = GooglePlaceSearch(
        apiKey: key,
        client: MockClient((request) async {
          seen = request;
          return http.Response(response, 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      await search.search('Taksim');
      expect((jsonDecode(seen.body) as Map).containsKey('locationBias'), isFalse);
    });

    test('hata PlaceSearchException; mesajda anahtar yok', () async {
      final search = GooglePlaceSearch(
        apiKey: key,
        client: MockClient((_) async => http.Response('$key hatası', 500)),
      );
      await expectLater(
        search.search('Taksim'),
        throwsA(isA<PlaceSearchException>().having((e) => e.toString(), 'toString', isNot(contains(key)))),
      );
    });
  });

  group('MapsConfig', () {
    test('anahtar yoksa (varsayılan derleme) hasKey false', () {
      expect(const MapsConfig().hasKey, isFalse);
      expect(const MapsConfig('   ').hasKey, isFalse);
      expect(const MapsConfig('abc').hasKey, isTrue);
    });
  });
}
