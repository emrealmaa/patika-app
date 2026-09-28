import 'dart:math' as math;

import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/route.dart';

/// Yerel metre koordinatı (x doğu, y kuzey) -> enlem/boylam. Test rotaları
/// metreyle düşünülüp yazılabilsin diye.
const _lat0 = 41.0, _lng0 = 29.0;
const _metersPerDegree = 111195.0;

LatLng enu(double x, double y) => LatLng(
      _lat0 + y / _metersPerDegree,
      _lng0 + x / (_metersPerDegree * math.cos(_lat0 * math.pi / 180)),
    );

/// Google'ın kodlanmış çoklu çizgi biçimi (`decodePolyline`'ın tersi):
/// Routes API örnek yanıtları üretmek için.
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var prevLat = 0, prevLng = 0;
  void write(int value) {
    var v = value < 0 ? ~(value << 1) : value << 1;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round(), lng = (p.lng * 1e5).round();
    write(lat - prevLat);
    write(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}

final _t0 = DateTime(2026, 9, 28, 12);

PositionFix fixAt(double x, double y, {double accuracy = 5, int seconds = 0}) =>
    PositionFix(enu(x, y), accuracy, _t0.add(Duration(seconds: seconds)));

DateTime at(int seconds) => _t0.add(Duration(seconds: seconds));

/// 470 m'lik deneme rotası (adım başlangıçları 0 / 200 / 350 / 370):
///
///   adım 0: kuzeye 200 m, Moda Caddesi (düz)
///   adım 1: 200. m'de sağa dön, doğuya 150 m, Bağdat Caddesi
///   adım 2: karşıya geçiş, doğuya 20 m
///   adım 3: 370. m'de sola dön, kuzeye 100 m, İskele Sokağı -> hedef
WalkingRoute testRoute() => WalkingRoute(
      destinationName: 'Kadıköy İskelesi',
      duration: const Duration(minutes: 6),
      steps: [
        RouteStep(
          maneuver: Maneuver.straight,
          streetName: 'Moda Caddesi',
          points: [enu(0, 0), enu(0, 200)],
        ),
        RouteStep(
          maneuver: Maneuver.right,
          streetName: 'Bağdat Caddesi',
          points: [enu(0, 200), enu(150, 200)],
        ),
        RouteStep(
          maneuver: Maneuver.straight,
          isCrossing: true,
          points: [enu(150, 200), enu(170, 200)],
        ),
        RouteStep(
          maneuver: Maneuver.left,
          streetName: 'İskele Sokağı',
          points: [enu(170, 200), enu(170, 300)],
        ),
      ],
    );

/// Köşe noktaları (x, y) boyunca [stepMeters]'lik adımlarla yürünen konumlar.
/// Köşe noktaları da listeye girer.
List<(double, double)> walkPath(List<(double, double)> corners, {double stepMeters = 10}) {
  final out = <(double, double)>[corners.first];
  for (var i = 1; i < corners.length; i++) {
    final (x0, y0) = corners[i - 1];
    final (x1, y1) = corners[i];
    final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final n = (len / stepMeters).floor();
    for (var s = 1; s <= n; s++) {
      final f = s * stepMeters / len;
      out.add((x0 + (x1 - x0) * f, y0 + (y1 - y0) * f));
    }
    if (n * stepMeters < len) out.add((x1, y1));
  }
  return out;
}

/// [path] boyunca birer saniye arayla okuma verir; tüm olayları sırayla döndürür.
List<GuidanceEvent> walk(GuidanceEngine engine, List<(double, double)> path, {double accuracy = 5}) {
  final events = <GuidanceEvent>[];
  for (var i = 0; i < path.length; i++) {
    events.addAll(engine.update(fixAt(path[i].$1, path[i].$2, accuracy: accuracy, seconds: i)));
  }
  return events;
}
