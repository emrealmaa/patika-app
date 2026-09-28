import 'dart:math' as math;

/// Enlem/boylam (derece). Navigasyonun tüm saf hesapları bunun üzerinde;
/// konum eklentisine ya da harita API'sine bağımlı değil.
class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

const _earthRadius = 6371000.0;

double _rad(double deg) => deg * math.pi / 180;

/// İki nokta arasındaki büyük daire uzaklığı (metre, haversine).
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

/// Google'ın kodlanmış çoklu çizgi biçimini (encoded polyline) çözer. Routes
/// API her adımın geometrisini bu biçimde veriyor.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Bir noktanın [a]-[b] doğru parçasına izdüşümü: [t] parçanın neresi
/// (0 = a, 1 = b), [distance] noktanın parçaya uzaklığı (metre).
///
/// Yürüme ölçeğindeki (onlarca-yüzlerce metre) parçalar için [a] çevresinde
/// düzlem yaklaşımı yeterince doğru; küresel hesap gerekmez.
({double t, double distance}) projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(_rad(a.lat));
  double x(LatLng q) => _rad(q.lng - a.lng) * cosLat * _earthRadius;
  double y(LatLng q) => _rad(q.lat - a.lat) * _earthRadius;

  final bx = x(b), by = y(b), px = x(p), py = y(p);
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - t * bx, dy = py - t * by;
  return (t: t, distance: math.sqrt(dx * dx + dy * dy));
}

/// [points] çizgisini başından [meters] uzaklıkta ikiye böler: baş kısım ve
/// kalan kısım kesim noktasını paylaşır. [meters] çizginin dışındaysa kalan
/// boş döner (bölünecek bir şey yok).
({List<LatLng> head, List<LatLng> tail}) splitPolyline(List<LatLng> points, double meters) {
  var remaining = meters;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final len = distanceMeters(a, b);
    if (remaining <= len && len > 0) {
      final t = remaining / len;
      final cut = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
      return (
        head: [...points.sublist(0, i), cut],
        tail: [cut, ...points.sublist(i)],
      );
    }
    remaining -= len;
  }
  return (head: points, tail: const []);
}

/// [a]'dan [b]'ye yön (radyan; kuzey 0, doğu π/2). Yürüme ölçeğinde düzlem
/// yaklaşımı yeterli.
double bearingRadians(LatLng a, LatLng b) {
  final dy = b.lat - a.lat;
  final dx = (b.lng - a.lng) * math.cos(_rad(a.lat));
  return math.atan2(dx, dy);
}

/// İki yön (radyan) arasındaki küçük açı farkı, 0-180 derece.
double angleDifferenceDegrees(double a, double b) {
  var d = (a - b).abs() % (2 * math.pi);
  if (d > math.pi) d = 2 * math.pi - d;
  return d * 180 / math.pi;
}
