import 'dart:collection';
import 'dart:math' as math;

import 'fall_config.dart';
import 'motion_sample.dart';

/// Bir düşme değerlendirmesinin sonucu. Sıra, dedektörün adımlarıdır: ilk
/// başarısız adım sonucu belirler.
enum FallOutcome {
  /// Serbest düşüş oldu ama ardından darbe gelmedi (telefon yatağa atıldı,
  /// yumuşak yere kondu). Gölge kaydına GİRMEZ, yalnızca sayılır.
  noImpact,

  /// Düşüş + darbe var, ama telefonun duruşu değişmedi.
  noOrientationChange,

  /// Düşüş + darbe + yön değişimi var, ama ardından hareket sürdü
  /// (telefon düşüp hemen alındı, kişi kalktı).
  movement,

  /// Dört adımın hepsi geçti: düşme adayı.
  candidate;

  /// Darbe adımına ulaştı mı? Gölge kaydına yalnızca bunlar girer
  /// (Faz 7c-1 kararı).
  bool get reachedImpact => this != noImpact;
}

/// Değerlendirmenin özeti: kayda yalnızca bu değerler girer (ham örnek ve
/// konum hiçbir zaman). Sonuç hangi adımda belirlenmiş olursa olsun ölçülebilen
/// değerlerin hepsi doldurulur: eşik ayarı için elenen adaylar da gerekli.
class FallEvaluation {
  final FallOutcome outcome;

  /// Değerlendirmenin başladığı an (serbest düşüş başlangıcı), sensör zamanı ms.
  final int startMs;

  /// Serbest düşüşün süresi (ms).
  final int freeFallMs;

  /// Düşüşten sonra görülen en yüksek ivme (g). Darbe olmasa da ölçülür.
  final double peakG;

  /// Düşme öncesi ile sonrası yerçekimi yönü arasındaki açı (derece). Darbe
  /// yoksa ya da düşme öncesi yeterli veri yoksa null.
  final double? orientationDegrees;

  /// Yerleşmeden sonraki penceredeki ivme büyüklüğünün standart sapması (g).
  /// Darbe yoksa null.
  final double? stillnessStdG;

  const FallEvaluation({
    required this.outcome,
    required this.startMs,
    required this.freeFallMs,
    required this.peakG,
    this.orientationDegrees,
    this.stillnessStdG,
  });

  @override
  String toString() => 'FallEvaluation($outcome, düşüş ${freeFallMs}ms, tepe '
      '${peakG.toStringAsFixed(2)}g, açı ${orientationDegrees?.toStringAsFixed(0)}, '
      'std ${stillnessStdG?.toStringAsFixed(3)})';
}

enum _Stage { idle, freeFall, awaitImpact, settling, observing }

/// Eşik tabanlı, 4 adımlı düşme dedektörü (Faz 7c): serbest düşüş → darbe →
/// yön değişimi → hareketsizlik. Saf mantık: örnekleri alır, değerlendirme
/// döndürür; zamanlayıcı, platform ya da SOS bilgisi yok.
///
/// Eşikler [FallConfig]'te ve **tamamen tahminidir** (gölge verisiyle
/// ayarlanacak). Bir değerlendirme sürerken yeni bir düşüş aranmaz; sonuç
/// verilince dedektör baştan başlar.
///
/// Örnekler arasında [FallConfig.sampleGap]'ten uzun boşluk (ekran kapalıyken
/// CPU uykusu gibi) yarım kalan değerlendirmeyi atar ve [gapCount]'u artırır:
/// eksik veriyle karar verilmez.
class FallDetector {
  final FallConfig config;

  FallDetector({this.config = const FallConfig()});

  _Stage _stage = _Stage.idle;
  int? _lastMs;
  int _gapCount = 0;

  /// Düşme öncesi yön için son [FallConfig.baselineWindow] kadar örnek
  /// (yalnızca beklerken dolar).
  final _history = ListQueue<MotionSample>();

  int _startMs = 0;
  int _freeFallEndMs = 0;
  int _impactMs = 0;
  int _observeFromMs = 0;
  double _peakG = 0;
  (double, double, double)? _baseline;
  final _observed = <MotionSample>[];

  /// Şimdiye dek görülen örnek kesintisi sayısı (telefon testi için).
  int get gapCount => _gapCount;

  /// Bir değerlendirme sürüyor mu (serbest düşüş başladı, sonuç yok)?
  bool get evaluating => _stage != _Stage.idle;

  /// Örnekleri sırayla işler; biten değerlendirmeleri döndürür.
  List<FallEvaluation> addAll(Iterable<MotionSample> samples) => [
        for (final s in samples) ?add(s),
      ];

  /// Tek örnek işler; bir değerlendirme bittiyse onu döndürür.
  FallEvaluation? add(MotionSample s) {
    final last = _lastMs;
    if (last != null) {
      // Yinelenen ya da geri giden zaman: yok sayılır.
      if (s.tMs <= last) return null;
      if (s.tMs - last > config.sampleGap.inMilliseconds) {
        _gapCount++;
        _reset();
      }
    }
    _lastMs = s.tMs;
    final g = s.magnitudeG;

    switch (_stage) {
      case _Stage.idle:
        if (g < config.freeFallBelowG) {
          _baseline = _baselineVector();
          _startMs = s.tMs;
          _peakG = g;
          _stage = _Stage.freeFall;
        } else {
          _history.addLast(s);
          while (_history.first.tMs < s.tMs - config.baselineWindow.inMilliseconds) {
            _history.removeFirst();
          }
        }
        return null;

      case _Stage.freeFall:
        if (g < config.freeFallBelowG) return null;
        final duration = s.tMs - _startMs;
        if (duration > config.freeFallMax.inMilliseconds) {
          // Çok uzun serbest düşüş insan düşmesi değil: bitince sessizce baştan.
          // (Süre aşılır aşılmaz sıfırlansaydı düşüşün kalanı, düşme öncesi
          // yönü bilinmeyen yeni bir düşüş gibi başlardı.)
          _reset();
          return null;
        }
        if (duration < config.freeFallMin.inMilliseconds) {
          // Kısa sarsıntı: değerlendirme yok, bekleme sürer (geçmiş korunur).
          _stage = _Stage.idle;
          _history.addLast(s);
          return null;
        }
        _freeFallEndMs = s.tMs;
        _peakG = g;
        if (g > config.impactAboveG) {
          _beginSettling(s);
        } else {
          _stage = _Stage.awaitImpact;
        }
        return null;

      case _Stage.awaitImpact:
        _peakG = math.max(_peakG, g);
        if (g > config.impactAboveG) {
          _beginSettling(s);
          return null;
        }
        if (s.tMs - _freeFallEndMs > config.impactWindow.inMilliseconds) {
          final e = FallEvaluation(
            outcome: FallOutcome.noImpact,
            startMs: _startMs,
            freeFallMs: _freeFallEndMs - _startMs,
            peakG: _peakG,
          );
          _reset();
          return e;
        }
        return null;

      case _Stage.settling:
        _peakG = math.max(_peakG, g);
        if (s.tMs - _impactMs >= config.settleDelay.inMilliseconds) {
          _observeFromMs = s.tMs;
          _observed.add(s);
          _stage = _Stage.observing;
        }
        return null;

      case _Stage.observing:
        _observed.add(s);
        if (s.tMs - _observeFromMs < config.stillnessWindow.inMilliseconds) return null;
        final e = _evaluate();
        _reset();
        return e;
    }
  }

  void _beginSettling(MotionSample s) {
    _impactMs = s.tMs;
    _peakG = math.max(_peakG, s.magnitudeG);
    _stage = _Stage.settling;
  }

  FallEvaluation _evaluate() {
    final orientEnd = _observeFromMs + config.orientationWindow.inMilliseconds;
    final after = _mean(_observed.where((s) => s.tMs < orientEnd));
    final before = _baseline;
    final degrees = (before == null || after == null) ? null : _angleDegrees(before, after);

    final mags = [for (final s in _observed) s.magnitudeG];
    final std = _std(mags);

    final outcome = (degrees == null || degrees < config.orientationMinDegrees)
        ? FallOutcome.noOrientationChange
        : std >= config.stillnessMaxStdG
            ? FallOutcome.movement
            : FallOutcome.candidate;
    return FallEvaluation(
      outcome: outcome,
      startMs: _startMs,
      freeFallMs: _freeFallEndMs - _startMs,
      peakG: _peakG,
      orientationDegrees: degrees,
      stillnessStdG: std,
    );
  }

  /// Düşme öncesi ortalama ivme vektörü. Geçmiş pencerenin en az yarısını
  /// kapsamıyorsa (dedektör yeni başladı, kesintiden hemen sonra) null:
  /// yön değişimi ölçülemez ve değerlendirme o adımda elenir.
  (double, double, double)? _baselineVector() {
    if (_history.isEmpty) return null;
    final span = _history.last.tMs - _history.first.tMs;
    if (span < config.baselineWindow.inMilliseconds ~/ 2) return null;
    return _mean(_history);
  }

  void _reset() {
    _stage = _Stage.idle;
    _history.clear();
    _observed.clear();
    _baseline = null;
    _peakG = 0;
  }

  static (double, double, double)? _mean(Iterable<MotionSample> samples) {
    var n = 0;
    var x = 0.0, y = 0.0, z = 0.0;
    for (final s in samples) {
      n++;
      x += s.x;
      y += s.y;
      z += s.z;
    }
    if (n == 0) return null;
    return (x / n, y / n, z / n);
  }

  static double? _angleDegrees((double, double, double) a, (double, double, double) b) {
    final la = math.sqrt(a.$1 * a.$1 + a.$2 * a.$2 + a.$3 * a.$3);
    final lb = math.sqrt(b.$1 * b.$1 + b.$2 * b.$2 + b.$3 * b.$3);
    // Ortalama vektör neredeyse sıfırsa yön anlamsız.
    if (la < 1e-6 || lb < 1e-6) return null;
    final cos = ((a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3) / (la * lb)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  static double _std(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sum = 0.0;
    for (final v in values) {
      sum += (v - mean) * (v - mean);
    }
    return math.sqrt(sum / values.length);
  }
}
