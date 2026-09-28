import 'geo.dart';
import 'route.dart';

/// Rota hesaplayıcı. Gerçek uygulama (Google Routes API, `--dart-define`
/// anahtarıyla) 6c'de gelecek; şimdilik `NavigationSession`'ın yeniden rota
/// hesaplaması bu arayüze dayanıyor ve testlerde sahtesi kullanılıyor.
/// Anahtar yoksa hiç kurulmaz: navigasyon yine başlar ama yeniden rota
/// hesaplanmaz (bkz. CLAUDE.md Faz 6 kararları).
abstract class RoutePlanner {
  /// [from]'dan [to]'ya yürüyüş rotası. Hesaplanamazsa [RoutePlanException].
  Future<WalkingRoute> plan({
    required LatLng from,
    required LatLng to,
    required String destinationName,
  });
}

class RoutePlanException implements Exception {
  final String message;
  const RoutePlanException(this.message);

  @override
  String toString() => 'RoutePlanException: $message';
}
