import 'geo.dart';

/// Yer araması sonucu ("Kadıköy İskelesi").
class PlaceCandidate {
  final String name;
  final String? address;
  final LatLng location;

  const PlaceCandidate({required this.name, this.address, required this.location});
}

/// Söylenen yeri ("Kadıköy iskelesi") koordinata çözer. Gerçek uygulama
/// Google Places API (New) Text Search; testlerde sahtesi kullanılır.
abstract class PlaceSearch {
  /// En fazla birkaç aday (sesle "hangisi?" diye sorulabilecek kadar).
  /// [near] verilirse yakın sonuçlar öne çıkar. Aramada hata olursa
  /// [PlaceSearchException].
  Future<List<PlaceCandidate>> search(String query, {LatLng? near});
}

class PlaceSearchException implements Exception {
  final String message;
  const PlaceSearchException(this.message);

  @override
  String toString() => 'PlaceSearchException: $message';
}
