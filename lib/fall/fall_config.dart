/// Düşme dedektörünün eşikleri (Faz 7c).
///
/// **BU DEĞERLERİN HEPSİ TAHMİNİDİR.** Literatür ve sağduyudan alınmış
/// başlangıç değerleridir; hiçbir gerçek düşme ya da gerçek kullanım
/// verisiyle doğrulanmamıştır. Gölge modunun kayıtlarıyla ayarlanacaktır
/// (bkz. CLAUDE.md "Faz 7c kararları" madde 5, docs/fall_detection_plan.md).
/// Testler değerleri değiştirebilsin diye sabit değil, kurucu parametresi.
class FallConfig {
  /// Serbest düşüş: ivme büyüklüğü bu değerin (g) altında. TAHMİNİ.
  final double freeFallBelowG;

  /// Serbest düşüş en az bu kadar sürmeli (daha kısası sarsıntıdır) ve en
  /// fazla bu kadar sürebilir (daha uzunu insan düşmesi değildir: fırlatma,
  /// yüksekten düşen telefon). TAHMİNİ.
  final Duration freeFallMin;
  final Duration freeFallMax;

  /// Darbe: serbest düşüş bittikten sonra [impactWindow] içinde büyüklük bu
  /// değerin (g) üstüne çıkmalı. TAHMİNİ.
  final double impactAboveG;
  final Duration impactWindow;

  /// Darbeden sonra sekme ve toparlanma için beklenen süre; yön ve
  /// hareketsizlik bundan sonra ölçülür. TAHMİNİ.
  final Duration settleDelay;

  /// Yön değişimi: düşme öncesi [baselineWindow] ile yerleşme sonrası ilk
  /// [orientationWindow] boyunca ortalama ivme vektörleri (yerçekimi yönü)
  /// arasındaki açı en az bu kadar (derece). TAHMİNİ.
  final double orientationMinDegrees;
  final Duration baselineWindow;
  final Duration orientationWindow;

  /// Hareketsizlik: yerleşmeden sonra [stillnessWindow] boyunca ivme
  /// büyüklüğünün standart sapması bu değerin (g) altında. TAHMİNİ.
  final double stillnessMaxStdG;
  final Duration stillnessWindow;

  /// Ardışık iki örnek arasında bundan uzun boşluk "kesinti" sayılır ve
  /// dedektör baştan başlar (ekran kapalıyken CPU uykusu; telefon testinde
  /// ölçülecek).
  final Duration sampleGap;

  const FallConfig({
    this.freeFallBelowG = 0.4,
    this.freeFallMin = const Duration(milliseconds: 80),
    this.freeFallMax = const Duration(milliseconds: 1000),
    this.impactAboveG = 2.5,
    this.impactWindow = const Duration(milliseconds: 500),
    this.settleDelay = const Duration(milliseconds: 1500),
    this.orientationMinDegrees = 45,
    this.baselineWindow = const Duration(milliseconds: 1000),
    this.orientationWindow = const Duration(milliseconds: 1000),
    this.stillnessMaxStdG = 0.1,
    this.stillnessWindow = const Duration(seconds: 5),
    this.sampleGap = const Duration(seconds: 1),
  });
}
