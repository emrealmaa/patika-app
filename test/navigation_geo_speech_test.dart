import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/guidance_speech.dart';
import 'package:patika_app/navigation/route.dart';

import 'navigation_fixtures.dart';

void main() {
  group('geo', () {
    test('haversine: 0,001 derece enlem ≈ 111 m', () {
      expect(distanceMeters(const LatLng(41, 29), const LatLng(41.001, 29)), closeTo(111.2, 0.3));
      expect(distanceMeters(const LatLng(41, 29), const LatLng(41, 29)), 0);
    });

    test('encoded polyline: Google\'ın belgelerindeki örnek', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points[0].lat, closeTo(38.5, 1e-9));
      expect(points[0].lng, closeTo(-120.2, 1e-9));
      expect(points[1].lat, closeTo(40.7, 1e-9));
      expect(points[1].lng, closeTo(-120.95, 1e-9));
      expect(points[2].lat, closeTo(43.252, 1e-9));
      expect(points[2].lng, closeTo(-126.453, 1e-9));
    });

    test('boş polyline boş liste verir', () {
      expect(decodePolyline(''), isEmpty);
    });

    test('doğru parçasına izdüşüm: orta, uç kenarı ve uzaklık', () {
      final a = enu(0, 0), b = enu(0, 100);

      var r = projectOnSegment(enu(10, 40), a, b);
      expect(r.t, closeTo(0.4, 1e-3));
      expect(r.distance, closeTo(10, 0.1));

      r = projectOnSegment(enu(0, 150), a, b); // parçanın ötesi -> b'ye kenetlenir
      expect(r.t, 1);
      expect(r.distance, closeTo(50, 0.1));

      r = projectOnSegment(enu(3, -20), a, b);
      expect(r.t, 0);
    });

    test('sıfır uzunluklu parça çökmez', () {
      final r = projectOnSegment(enu(5, 5), enu(0, 0), enu(0, 0));
      expect(r.t, 0);
      expect(r.distance, closeTo(7.07, 0.1));
    });
  });

  group('formatDistance: sahte kesinlik yok', () {
    test('yakında 5 m, ortada 10 m, uzakta 50 m adımlarına yuvarlanır', () {
      expect(formatDistance(2), '5 metre');
      expect(formatDistance(12), '10 metre');
      expect(formatDistance(13), '15 metre');
      expect(formatDistance(47), '50 metre');
      expect(formatDistance(72), '70 metre');
      expect(formatDistance(130), '150 metre');
      expect(formatDistance(320), '300 metre');
      expect(formatDistance(960), '950 metre');
    });

    test('1 km ve üstü ondalıklı kilometre, Türkçe virgülle', () {
      expect(formatDistance(980), '1 kilometre');
      expect(formatDistance(1234), '1,2 kilometre');
      expect(formatDistance(2000), '2 kilometre');
    });
  });

  group('formatDuration', () {
    test('dakika, saat ve "bir dakikadan az"', () {
      expect(formatDuration(const Duration(seconds: 20)), 'bir dakikadan az');
      expect(formatDuration(const Duration(minutes: 15)), 'yaklaşık 15 dakika');
      expect(formatDuration(const Duration(minutes: 60)), 'yaklaşık 1 saat');
      expect(formatDuration(const Duration(minutes: 70)), 'yaklaşık 1 saat 10 dakika');
    });
  });

  group('describeEvent: bilgi kipi', () {
    test('dönüş: "30 metre sonra rota sağa sapıyor, Bağdat Caddesi"', () {
      expect(
        describeEvent(const ManeuverAhead(Maneuver.right, 'Bağdat Caddesi', 30)),
        '30 metre sonra rota sağa sapıyor, Bağdat Caddesi',
      );
    });

    test('sokak adı yoksa yalnızca mesafe + manevra; 5 m altında mesafe söylenmez', () {
      expect(describeEvent(const ManeuverAhead(Maneuver.left, null, 15)), '15 metre sonra rota sola sapıyor');
      expect(describeEvent(const ManeuverAhead(Maneuver.left, 'İskele Sokağı', 0)),
          'rota sola sapıyor, İskele Sokağı');
    });

    test('her manevranın bir cümlesi var', () {
      for (final m in Maneuver.values) {
        expect(describeEvent(ManeuverAhead(m, null, 30)), isNotEmpty);
      }
    });

    test('yön teyidi: bilgi kipinde üç cümle', () {
      expect(describeEvent(const DirectionInfo(DirectionVerdict.along)), 'Rota yönündesiniz');
      expect(describeEvent(const DirectionInfo(DirectionVerdict.opposite)),
          'Rotanın tersi yönündesiniz');
      expect(describeEvent(const DirectionInfo(DirectionVerdict.across)), 'Rotaya yan yöndesiniz');
    });

    test('geçiş, varış, rota dışı, konum', () {
      expect(describeEvent(const CrossingAhead(48)), '50 metre sonra karşıya geçiş noktası');
      expect(describeEvent(const CrossingPoint()), contains('Navigasyon duraklatıldı'));
      expect(describeEvent(const CrossingPoint()), contains('gözlüğe çift dokunun'));
      expect(describeEvent(const CrossingResumed()), 'Navigasyon devam ediyor');
      expect(describeEvent(const CrossingTimedOut()), 'Süre doldu, navigasyon devam ediyor');
      expect(describeEvent(const NearDestination(48)), 'Hedefe 50 metre kaldı');
      expect(describeEvent(const Arrived()), 'Hedef çevresindesiniz');
      expect(describeEvent(const OffRoute()), 'Rotanın dışındasınız');
      expect(describeEvent(const BackOnRoute()), 'Yeniden rotadasınız');
      expect(describeEvent(const GpsWeak()), 'Konum belirsiz');
      expect(describeEvent(const GpsRecovered()), 'Konum yeniden alındı');
    });
  });

  group('özet ve kalan', () {
    test('rota özeti: hedef, mesafe, süre, ilk sokak', () {
      expect(
        describeRouteSummary(testRoute()),
        'Kadıköy İskelesi, 450 metre, yaklaşık 6 dakika. Rota Moda Caddesi boyunca 200 metre',
      );
    });

    test('yön teyidi açıksa özetin sonuna "yön bilgisi yürümeye başlayınca gelecek" eklenir', () {
      expect(
        describeRouteSummary(testRoute(), withDirectionNote: true),
        'Kadıköy İskelesi, 450 metre, yaklaşık 6 dakika. Rota Moda Caddesi boyunca 200 metre. '
        'Yön bilgisi yürümeye başlayınca gelecek',
      );
    });

    test('ilk adımın sokağı yoksa yalnızca özet', () {
      final route = WalkingRoute(
        destinationName: 'Yer',
        duration: const Duration(minutes: 2),
        steps: [RouteStep(maneuver: Maneuver.straight, points: [enu(0, 0), enu(0, 100)])],
      );
      expect(describeRouteSummary(route), 'Yer, 100 metre, yaklaşık 2 dakika');
    });

    test('"ne kadar kaldı"', () {
      final engine = GuidanceEngine(testRoute());
      expect(describeRemaining(engine), 'Hedefe 450 metre, yaklaşık 6 dakika kaldı');
    });
  });
}
