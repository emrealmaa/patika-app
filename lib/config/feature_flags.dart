/// Derleme zamanı özellik bayrakları. Değerler koda gömülmüyor,
/// `--dart-define-from-file=dart_defines.json` ile veriliyor (örnek:
/// `dart_defines.example.json`). Aynı yol ileride API anahtarları için de
/// kullanılacak - `dart_defines.json` git'e girmiyor.
abstract final class FeatureFlags {
  /// Onaydan sonra ACTION_CALL ile doğrudan arama (Faz 4). Google Play
  /// CALL_PHONE iznini kısıtladığı için varsayılan kapalı; kapalıyken
  /// mevcut `tel:` akışı (arama ekranını açma) çalışır.
  static const directCall = bool.fromEnvironment('PATIKA_DIRECT_CALL');

  /// SmsManager ile doğrudan SMS (Faz 4). SEND_SMS aynı Play kısıtına
  /// tabi; kapalıyken mevcut `sms:` akışı çalışır.
  static const directSms = bool.fromEnvironment('PATIKA_DIRECT_SMS');
}
