import 'geo.dart';
import 'place_search.dart';
import 'route.dart';
import 'route_planner.dart';

/// Google Routes API (`computeRoutes`) ve Places API (New) yanıtlarının saf
/// ayrıştırması: ağdan bağımsız, kayıtlı örnek JSON'larla test edilir.
///
/// İki bilinçli sınır:
/// - Google'ın `navigationInstruction.instructions` metni **asla
///   seslendirilmez** (emir kipinde; bkz. CLAUDE.md Faz 6 kararları, madde 1).
///   Yalnızca (a) manevra enum'u, (b) karşıya geçiş tespiti için okunur.
/// - Routes API'de yapısal sokak adı alanı YOK (belgeler: `RouteLegStep` ve
///   `NavigationInstruction` yalnızca manevra + serbest metin taşır).
///   Serbest metinden sokak adı ayıklamak kırılgan olacağından duyurularda
///   sokak adı yok ([RouteStep.streetName] null).

/// Karşıya geçiş olarak işaretlenen bir adım bu kadar uzunsa (metre) yalnızca
/// başındaki [crossingSplitMeters] geçiş sayılır, kalanı normal yürüyüştür:
/// Google'ın adımı geçişten sonra da sürebilir ve duraklama uzamasın.
const maxCrossingStepMeters = 30.0;
const crossingSplitMeters = 20.0;

/// Google manevra enum'u -> [Maneuver]. Duyurulmayan/anlamsız olanlar
/// ("devam", "yol adı değişti", "birleş") [Maneuver.straight] (sessiz);
/// yürüyüşte nadir karmaşık olanlar (rampa, çatal, döner kavşak, feribot)
/// [Maneuver.other].
Maneuver mapManeuver(String? raw) => switch (raw) {
      'TURN_LEFT' => Maneuver.left,
      'TURN_SLIGHT_LEFT' => Maneuver.slightLeft,
      'TURN_SHARP_LEFT' => Maneuver.sharpLeft,
      'TURN_RIGHT' => Maneuver.right,
      'TURN_SLIGHT_RIGHT' => Maneuver.slightRight,
      'TURN_SHARP_RIGHT' => Maneuver.sharpRight,
      'UTURN_LEFT' || 'UTURN_RIGHT' => Maneuver.uTurn,
      null ||
      'MANEUVER_UNSPECIFIED' ||
      'STRAIGHT' ||
      'DEPART' ||
      'NAME_CHANGE' ||
      'MERGE' =>
        Maneuver.straight,
      _ => Maneuver.other,
    };

final _crossingPattern = RegExp(
  r'karşıya|karşı\s+(?:tarafa|kaldırıma)|yaya\s+geçi[dt]|\bcross',
  caseSensitive: false,
);

/// Adımın talimat metni bir karşıya geçişten söz ediyor mu? SEZGİSEL: metin
/// yalnızca bu tespit için okunur, hiçbir yerde seslendirilmez. Yanlış
/// pozitif navigasyonu gereksiz duraklatır (güvenli tarafta hata); yanlış
/// negatif duraklatmaz - ama navigasyon zaten hiçbir güvenlik kararı
/// vermez, geçiş kararı Kavşak Geçiş Asistanına aittir.
bool looksLikeCrossing(String? instructions) {
  if (instructions == null || instructions.isEmpty) return false;
  final text = instructions.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  return _crossingPattern.hasMatch(text);
}

/// "900s", "12.5s" -> Duration. Bozuksa null.
Duration? parseGoogleDuration(Object? raw) {
  if (raw is! String || !raw.endsWith('s')) return null;
  final seconds = double.tryParse(raw.substring(0, raw.length - 1));
  return seconds == null ? null : Duration(milliseconds: (seconds * 1000).round());
}

/// `computeRoutes` yanıtından [WalkingRoute]. Rota yoksa ya da bozuksa
/// [RoutePlanException].
WalkingRoute parseRoutesResponse(Map<String, dynamic> json, {required String destinationName}) {
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty || routes.first is! Map) {
    throw const RoutePlanException('rota bulunamadı');
  }
  final route = (routes.first as Map).cast<String, dynamic>();

  final steps = <RouteStep>[];
  final legs = route['legs'];
  if (legs is List) {
    for (final leg in legs.whereType<Map>()) {
      final legSteps = leg['steps'];
      if (legSteps is! List) continue;
      for (final raw in legSteps.whereType<Map>()) {
        steps.addAll(_parseStep(raw.cast<String, dynamic>()));
      }
    }
  }
  if (steps.isEmpty) throw const RoutePlanException('rota adımı yok');

  final duration = parseGoogleDuration(route['duration']) ?? _walkingEstimate(steps);
  return WalkingRoute(destinationName: destinationName, steps: steps, duration: duration);
}

/// Google'ın süresi gelmezse ~1,25 m/sn yürüme hızı.
Duration _walkingEstimate(List<RouteStep> steps) {
  final meters = steps.fold<double>(0, (sum, s) => sum + s.lengthMeters);
  return Duration(seconds: (meters / 1.25).round());
}

List<RouteStep> _parseStep(Map<String, dynamic> step) {
  final polyline = step['polyline'];
  final encoded = polyline is Map ? polyline['encodedPolyline'] : null;
  final points = encoded is String && encoded.isNotEmpty ? decodePolyline(encoded) : <LatLng>[];
  if (points.length < 2) return const [];

  final instruction = step['navigationInstruction'];
  final maneuver = instruction is Map ? instruction['maneuver'] as String? : null;
  final text = instruction is Map ? instruction['instructions'] as String? : null;
  final crossing = looksLikeCrossing(text);
  final mapped = mapManeuver(maneuver);

  final part = RouteStep(maneuver: mapped, points: points, isCrossing: crossing);
  if (!crossing || part.lengthMeters <= maxCrossingStepMeters) return [part];

  final split = splitPolyline(points, crossingSplitMeters);
  if (split.tail.length < 2) return [part];
  return [
    RouteStep(maneuver: mapped, points: split.head, isCrossing: true),
    RouteStep(maneuver: Maneuver.straight, points: split.tail),
  ];
}

/// Places API (New) Text Search yanıtından adaylar. Konumu olmayanlar atlanır.
List<PlaceCandidate> parsePlacesResponse(Map<String, dynamic> json) {
  final places = json['places'];
  if (places is! List) return const [];
  final out = <PlaceCandidate>[];
  for (final raw in places.whereType<Map>()) {
    final name = raw['displayName'];
    final text = name is Map ? name['text'] : null;
    final location = raw['location'];
    if (text is! String || text.isEmpty || location is! Map) continue;
    final lat = location['latitude'], lng = location['longitude'];
    if (lat is! num || lng is! num) continue;
    out.add(PlaceCandidate(
      name: text,
      address: raw['formattedAddress'] as String?,
      location: LatLng(lat.toDouble(), lng.toDouble()),
    ));
  }
  return out;
}
