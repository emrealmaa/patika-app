/// Google Routes/Places API anahtarı. Koda gömülmez: derleme sırasında
/// `--dart-define` ile verilir (örnek: `dart_defines.example.json`, gerçek
/// değerler `dart_defines.json`'da, o dosya git'e girmez).
///
///   flutter run --flavor play --dart-define-from-file=dart_defines.json
///
/// Anahtar yoksa navigasyon Google Haritalar uygulamasını açan eski yedek
/// akışla çalışır (bkz. `NavigationBackend`).
class MapsConfig {
  final String apiKey;

  const MapsConfig([this.apiKey = const String.fromEnvironment('PATIKA_MAPS_API_KEY')]);

  bool get hasKey => apiKey.trim().isNotEmpty;
}
