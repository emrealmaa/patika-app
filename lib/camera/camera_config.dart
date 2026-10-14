/// Gözlük kamerası akışının ayarlanabilir değerleri. Hepsi **taslak**:
/// gerçek ESP32 ile gecikme/kare kaybı ölçülünce ayarlanacak (bkz. CLAUDE.md
/// "Bekleyen telefon testleri"). Kodda hiçbir yerde sabit değer yok; testler
/// kendi değerlerini verir.
class CameraConfig {
  /// MJPEG akış adresi (gözlük SoftAP'ında). Varsayılan ESP32 SoftAP adresi
  /// (192.168.4.1) ve ESP32 kamera örneğinin akış portu; firmware'de
  /// netleşecek. `--dart-define=PATIKA_GLASSES_STREAM_URL=...` ile değişir.
  final String streamUrl;

  /// Tazelik bekçisi: bundan eski kare tüketiciye hiç verilmez (patika
  /// Python roadmap'indeki ~400 ms "freshness guard" ile aynı fikir).
  final Duration freshness;

  /// Telefonun işleyeceği en yüksek kare hızı: daha sık gelen kareler
  /// ayrıştırıldıktan sonra atılır (işlemci/pil). Gözlüğe iletimi (kamera
  /// tarafında kare hızı düşürme) firmware'de netleşecek.
  final int maxFps;

  /// İstenen çözünürlük (taslak; gözlüğe nasıl iletileceği firmware'de).
  final CameraResolution resolution;

  /// Bundan büyük kare bozuk sayılır ve atılır (bellek koruması).
  final int maxFrameBytes;

  /// Akış açıkken bu süre kare gelmezse "görüntü gelmiyor" denir (bir kez).
  final Duration stallTimeout;

  /// `frm on` sonrası gözlüğün ağ bilgisini göndermesi için en fazla bekleme.
  final Duration credentialsTimeout;

  /// Ağ açıkken akış bağlantısı kapanırsa yeniden açmadan önce bekleme.
  final Duration reopenDelay;

  const CameraConfig({
    this.streamUrl = const String.fromEnvironment('PATIKA_GLASSES_STREAM_URL',
        defaultValue: 'http://192.168.4.1:81/stream'),
    this.freshness = const Duration(milliseconds: 400),
    this.maxFps = 10,
    this.resolution = CameraResolution.qvga,
    this.maxFrameBytes = 512 * 1024,
    this.stallTimeout = const Duration(seconds: 3),
    this.credentialsTimeout = const Duration(seconds: 10),
    this.reopenDelay = const Duration(seconds: 2),
  });

  /// İki kare arasındaki en kısa süre ([maxFps]'ten).
  Duration get minFrameInterval =>
      maxFps <= 0 ? Duration.zero : Duration(microseconds: 1000000 ~/ maxFps);
}

enum CameraResolution {
  qvga(320, 240),
  vga(640, 480);

  final int width;
  final int height;
  const CameraResolution(this.width, this.height);
}
