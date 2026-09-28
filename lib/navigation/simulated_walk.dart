import 'dart:math' as math;

import 'geo.dart';
import 'route.dart';

/// Test Modu için: bir rota boyunca "yürüyen" sahte kullanıcı. Gerçek GPS
/// yokken (ve yürümeden) navigasyonun uçtan uca denenmesini sağlar. Saf
/// mantık - konum servisi ve ekran bilmez.
class RouteWalker {
  final WalkingRoute route;
  double _offset = 0;

  RouteWalker(this.route);

  /// Rota boyunca gidilen mesafe (metre).
  double get offset => _offset;
  double get total => route.lengthMeters;
  bool get atEnd => _offset >= total;

  /// [meters] kadar ilerler (rotanın sonunda durur).
  void advance(double meters) => _offset = math.min(total, math.max(0, _offset + meters));

  /// Rotanın şu anki noktasındaki konum.
  LatLng get position => _pointAt(_offset).point;

  /// Şu anki noktadan rotaya dik [meters] kadar yanda konum (rotadan sapma).
  LatLng offRoute(double meters) {
    final (:point, :heading) = _pointAt(_offset);
    // Rotaya dik: yönü 90° döndür.
    final side = heading + math.pi / 2;
    final dLat = meters * math.cos(side) / 111195.0;
    final dLng = meters * math.sin(side) / (111195.0 * math.cos(point.lat * math.pi / 180));
    return LatLng(point.lat + dLat, point.lng + dLng);
  }

  ({LatLng point, double heading}) _pointAt(double offset) {
    var remaining = offset;
    LatLng? last;
    var heading = 0.0;
    for (final step in route.steps) {
      final pts = step.points;
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final len = distanceMeters(a, b);
        heading = bearingRadians(a, b);
        if (remaining <= len && len > 0) {
          final t = remaining / len;
          return (
            point: LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t),
            heading: heading,
          );
        }
        remaining -= len;
        last = b;
      }
    }
    return (point: last ?? route.start, heading: heading);
  }
}

/// Test Modu'nun deneme rotası: kuzeye 200 m, sağa dönüp doğuya 150 m,
/// karşıya geçiş (20 m), sola dönüp kuzeye 100 m. Sokak adları uydurma; gerçek
/// bir yer değil.
WalkingRoute demoRoute() {
  const base = LatLng(40.9900, 29.0230);
  LatLng at(double east, double north) => LatLng(
        base.lat + north / 111195.0,
        base.lng + east / (111195.0 * math.cos(base.lat * math.pi / 180)),
      );
  return WalkingRoute(
    destinationName: 'Deneme hedefi',
    duration: const Duration(minutes: 6),
    steps: [
      RouteStep(
        maneuver: Maneuver.straight,
        streetName: 'Deneme Caddesi',
        points: [at(0, 0), at(0, 200)],
      ),
      RouteStep(
        maneuver: Maneuver.right,
        streetName: 'Örnek Sokak',
        points: [at(0, 200), at(150, 200)],
      ),
      RouteStep(
        maneuver: Maneuver.straight,
        isCrossing: true,
        points: [at(150, 200), at(170, 200)],
      ),
      RouteStep(
        maneuver: Maneuver.left,
        streetName: 'Test Sokağı',
        points: [at(170, 200), at(170, 300)],
      ),
    ],
  );
}
