/// SOS'un başlattığı arama bitene kadar bekler. Arama sürerken uygulama
/// KONUŞMAZ (kullanıcı karşıdaki kişiyi duyuyor); geç kalan ya da başarısız
/// SMS sonuçları arama bittikten sonra özetlenir.
abstract class SosCallMonitor {
  Future<void> untilCallEnds();
}

/// **Geçici uygulama:** gerçek arama sonu tespiti (READ_PHONE_STATE ile
/// `TelephonyManager`) henüz yazılmadı; o zamana dek arama başladıktan
/// [delay] sonra bitmiş sayılır. Uzun aramada özet konuşma araya girebilir,
/// bkz. CLAUDE.md "Bekleyen telefon testleri".
class FixedDelayCallMonitor implements SosCallMonitor {
  final Duration delay;

  const FixedDelayCallMonitor([this.delay = const Duration(seconds: 120)]);

  @override
  Future<void> untilCallEnds() => Future<void>.delayed(delay);
}
