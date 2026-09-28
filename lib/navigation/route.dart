import 'geo.dart';

/// Rotadaki bir dönüş türü. Google'ın kendi manevra sözcükleri (6c'de
/// çevrilecek) ya da talimat metni buraya sızmaz: cümleyi biz kurarız
/// (bkz. `guidance_speech.dart`). Bilinmeyen/karmaşık manevralar
/// (çevre yolu, rampa, kavşak) [other]'a düşer.
enum Maneuver {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  other,
}

/// Rotanın bir adımı. Google Routes ile aynı anlam: [maneuver] adımın
/// **başında** yapılan dönüştür, [points] o noktadan adımın sonuna kadar
/// yürünen yoldur, [streetName] dönüşten sonra girilen sokaktır.
class RouteStep {
  final Maneuver maneuver;
  final String? streetName;
  final List<LatLng> points;

  /// Bu adım bir karşıya geçiş mi? Yalnızca sezgisel bir tahmin (6c'de
  /// Google'ın adım metninden çıkarılır): navigasyon geçiş kararı vermez,
  /// bu noktada susup kararı Kavşak Geçiş Asistanına bırakır.
  final bool isCrossing;

  RouteStep({
    required this.maneuver,
    required this.points,
    this.streetName,
    this.isCrossing = false,
  }) : assert(points.length >= 2, 'bir adım en az iki noktadan oluşur');

  late final double lengthMeters = _polylineLength(points);
}

/// Hesaplanmış bir yürüyüş rotası.
class WalkingRoute {
  final String destinationName;
  final List<RouteStep> steps;

  /// Google'ın tahmini yürüme süresi.
  final Duration duration;

  WalkingRoute({
    required this.destinationName,
    required this.steps,
    required this.duration,
  }) : assert(steps.isNotEmpty, 'rota en az bir adım içerir');

  late final double lengthMeters = steps.fold<double>(0, (sum, s) => sum + s.lengthMeters);

  LatLng get start => steps.first.points.first;
  LatLng get end => steps.last.points.last;
}

double _polylineLength(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distanceMeters(points[i - 1], points[i]);
  }
  return total;
}
