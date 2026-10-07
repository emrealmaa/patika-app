import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_identity.dart';
import 'geo.dart';
import 'google_parsing.dart';
import 'place_search.dart';
import 'route.dart';
import 'route_planner.dart';

/// Google Routes API istemcisi (yürüyüş rotası). Anahtar `X-Goog-Api-Key`
/// başlığıyla gider (adrese yazılmaz, günlüklere sızmaz). Hata mesajlarında
/// anahtar bulunmaz. Ağ/HTTP/ayrıştırma hataları tek türe çevrilir
/// ([RoutePlanException]) - çağıran yedek akışa düşer.
class GoogleRoutePlanner implements RoutePlanner {
  static final _endpoint = Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes');

  /// Yalnızca gereken alanlar (kota/maliyet ve gizlilik): süre + adım
  /// çizgisi + manevra/talimat (geçiş tespiti için).
  static const _fieldMask = 'routes.duration,'
      'routes.legs.steps.polyline.encodedPolyline,'
      'routes.legs.steps.navigationInstruction';

  final String apiKey;
  final http.Client _client;
  final Duration timeout;
  final AppIdentitySource? _identity;

  GoogleRoutePlanner({
    required this.apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    AppIdentitySource? identity,
  })  : _client = client ?? http.Client(),
        _identity = identity;

  @override
  Future<WalkingRoute> plan({
    required LatLng from,
    required LatLng to,
    required String destinationName,
  }) async {
    final json = await _post(
      _client,
      _endpoint,
      apiKey,
      _fieldMask,
      {
        'origin': _waypoint(from),
        'destination': _waypoint(to),
        'travelMode': 'WALK',
        'languageCode': 'tr',
        'units': 'METRIC',
      },
      timeout,
      (message) => RoutePlanException(message),
      await appRestrictionHeaders(_identity),
    );
    return parseRoutesResponse(json, destinationName: destinationName);
  }

  static Map<String, dynamic> _waypoint(LatLng p) => {
        'location': {
          'latLng': {'latitude': p.lat, 'longitude': p.lng},
        },
      };
}

/// Google Places API (New) Text Search istemcisi.
class GooglePlaceSearch implements PlaceSearch {
  static final _endpoint = Uri.parse('https://places.googleapis.com/v1/places:searchText');
  static const _fieldMask = 'places.displayName,places.formattedAddress,places.location';

  /// Sesle "hangisi?" diye sorulabilecek en fazla aday.
  static const maxResults = 3;

  /// Konuma yakın sonuçlar öne çıksın (yalnızca öncelik; uzağı elemez).
  static const biasRadiusMeters = 5000.0;

  final String apiKey;
  final http.Client _client;
  final Duration timeout;
  final AppIdentitySource? _identity;

  GooglePlaceSearch({
    required this.apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    AppIdentitySource? identity,
  })  : _client = client ?? http.Client(),
        _identity = identity;

  @override
  Future<List<PlaceCandidate>> search(String query, {LatLng? near}) async {
    final json = await _post(
      _client,
      _endpoint,
      apiKey,
      _fieldMask,
      {
        'textQuery': query,
        'languageCode': 'tr',
        'regionCode': 'TR',
        'maxResultCount': maxResults,
        if (near != null)
          'locationBias': {
            'circle': {
              'center': {'latitude': near.lat, 'longitude': near.lng},
              'radius': biasRadiusMeters,
            },
          },
      },
      timeout,
      (message) => PlaceSearchException(message),
      await appRestrictionHeaders(_identity),
    );
    return parsePlacesResponse(json);
  }
}

Future<Map<String, dynamic>> _post(
  http.Client client,
  Uri url,
  String apiKey,
  String fieldMask,
  Map<String, dynamic> body,
  Duration timeout,
  Exception Function(String message) fail,
  Map<String, String> extraHeaders,
) async {
  final http.Response response;
  try {
    response = await client
        .post(
          url,
          headers: {
            ...extraHeaders,
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask': fieldMask,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  } on TimeoutException {
    throw fail('zaman aşımı');
  } on http.ClientException catch (e) {
    throw fail('ağ hatası: ${e.message}');
  } catch (e) {
    // SocketException vb. (dart:io, web'de yok - o yüzden tür adıyla yakalanmıyor).
    throw fail('ağ hatası: ${e.runtimeType}');
  }

  if (response.statusCode != 200) {
    throw fail('HTTP ${response.statusCode}');
  }
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // aşağıdaki hata
  }
  throw fail('yanıt çözülemedi');
}
