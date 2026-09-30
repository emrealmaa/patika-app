import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fall_config.dart';
import 'fall_detector.dart';
import 'motion_sample.dart';
import 'motion_source.dart';

/// Test Modu'nun sentetik düğmelerinin kaynak adı. Bu kaynak açık modda da
/// **asla** gerçek eyleme bağlanmaz (karar 11); köprü bu adı ayrıca süzer.
const fallSyntheticSourceId = 'synthetic';

/// Düşme değerlendirmelerinin kaynağı (Faz 7c). Kayıt ve (7c-2'de) SOS
/// bağlantısı yalnızca bu arayüzü bilir; değerlendirmenin nereden geldiğini
/// bilmez.
///
/// Bugün tek uygulama telefon IMU'su ([PhoneImuFallCandidateSource]). Gerçek
/// çözüm muhtemelen **gözlük IMU'su** (başa bağlı, cepten bağımsız; TODO.md
/// madde 18): o geldiğinde ikinci bir uygulama olarak yazılır (BLE'den gelen
/// örnekleri ya da gözlüğün kendi aday özetini [FallEvaluation]'a çevirir),
/// kayıt ve monitör değişmez. Kaynak adı ([sourceId]) kayda yazılır; iki
/// kaynağın verisi ayrı ayarlanabilsin.
abstract class FallCandidateSource {
  /// Kayda yazılan kaynak adı (`phone_imu`, `synthetic`, ileride `glasses_imu`).
  String get sourceId;

  /// Biten değerlendirmeler (her sonuç; ne kaydedileceğine alıcı karar verir).
  Stream<FallEvaluation> get evaluations;

  /// Şimdiye dek görülen örnek kesintisi sayısı (telefon testi için).
  int get gapCount;

  bool get running;

  /// Başlatır. Kaynak kullanılamıyorsa (sensör yok) false; zaten çalışıyorsa true.
  Future<bool> start();

  Future<void> stop();

  Future<void> dispose();
}

/// Telefonun ivmeölçeri + [FallDetector].
class PhoneImuFallCandidateSource implements FallCandidateSource {
  final MotionSource _motion;
  final FallConfig _config;

  @override
  final String sourceId;

  final _out = StreamController<FallEvaluation>.broadcast();
  StreamSubscription<List<MotionSample>>? _sub;
  FallDetector? _detector;
  Future<bool>? _starting;
  int _earlierGaps = 0;

  PhoneImuFallCandidateSource(
    this._motion, {
    this.sourceId = 'phone_imu',
    FallConfig config = const FallConfig(),
  }) : _config = config;

  @override
  Stream<FallEvaluation> get evaluations => _out.stream;

  @override
  int get gapCount => _earlierGaps + (_detector?.gapCount ?? 0);

  @override
  bool get running => _sub != null;

  @override
  Future<bool> start() {
    if (running) return Future.value(true);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<bool> _start() async {
    if (!await _motion.available()) return false;
    if (running) return true;
    // Her başlatmada yeni dedektör: durdurup başlatmak "kesinti" sayılmasın,
    // yarım kalan değerlendirme de yeni akışa taşınmasın.
    _retireDetector();
    final detector = FallDetector(config: _config);
    _detector = detector;
    _sub = _motion.samples().listen(
      (batch) {
        for (final e in detector.addAll(batch)) {
          _out.add(e);
        }
      },
      onError: (Object e) {
        // Sensör açılamadı ya da koptu: sessizce ölü bir "çalışıyor" durumu
        // kalmasın. Monitör [running]'e bakıp durumu gösterir.
        debugPrint('[Düşme] sensör akışı hatası: ${e.runtimeType}');
        unawaited(stop());
      },
      onDone: () => unawaited(stop()),
    );
    return true;
  }

  @override
  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    // İptali beklemiyoruz: abonelik bu çağrıda hemen kalkar (sensör kapanır);
    // dönen Future yalnızca native tarafın onayı. Beklemek, sırayla işlenen
    // mod değişimlerini ve sentetik düğmeleri o onaya bağlardı.
    if (sub != null) unawaited(sub.cancel());
  }

  void _retireDetector() {
    _earlierGaps += _detector?.gapCount ?? 0;
    _detector = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}
