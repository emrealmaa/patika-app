import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fall_candidate_source.dart';
import 'fall_detector.dart';
import 'fall_mode.dart';
import 'fall_shadow_log.dart';

/// Düşme algılamanın gölge monitörü (Faz 7c-1): moda göre aday kaynağını
/// başlatır/durdurur, sonuçları gölge kaydına yazar, isteğe bağlı test ses
/// işareti çalar. **Başka hiçbir şey yapmaz.**
///
/// Bu sınıfın SOS'la hiçbir bağlantısı yoktur: `SosController` ya da herhangi
/// bir SOS türü bu dosyada içe aktarılmaz, kurucuda alınmaz. Düşme algılamanın
/// SOS'a bağlanması 7c-2'nin işidir (ve [FallMode]'da `on` değeri olmadan
/// mümkün değildir). `fall_monitor_test.dart` bunu kilitler.
class FallMonitor extends ChangeNotifier {
  final FallCandidateSource _source;
  final FallShadowLog log;

  /// Test ses işaretini çalar (aday oluşunca). Null ise hiç çalmaz.
  final void Function()? _playCandidateEarcon;
  final bool Function() _earconEnabled;

  StreamSubscription<FallEvaluation>? _sub;
  FallMode _mode = FallMode.off;
  bool _sensorUnavailable = false;
  bool _disposed = false;
  Future<void> _tail = Future.value();

  /// Darbeye ulaşmadan biten değerlendirmeler (kayda girmez, yalnızca sayılır).
  int noImpactCount = 0;

  FallMonitor({
    required FallCandidateSource source,
    required this.log,
    void Function()? playCandidateEarcon,
    bool Function()? earconEnabled,
  })  : _source = source,
        _playCandidateEarcon = playCandidateEarcon,
        _earconEnabled = earconEnabled ?? (() => false) {
    _sub = _source.evaluations.listen(_onEvaluation);
  }

  FallMode get mode => _mode;

  /// Gölge modu istendi ama cihazda ivmeölçer yok / açılamadı.
  bool get sensorUnavailable => _sensorUnavailable;

  /// Kaynak şu an çalışıyor mu?
  bool get running => _source.running;

  /// Bu oturumda görülen örnek kesintisi sayısı (telefon testi).
  int get gapCount => _source.gapCount;

  /// Modu uygular: `shadow` kaynağı başlatır, `off` durdurur. Art arda
  /// çağrılar sırayla işlenir.
  Future<void> setMode(FallMode mode) {
    _tail = _tail.then((_) => _apply(mode));
    return _tail;
  }

  Future<void> _apply(FallMode mode) async {
    if (_disposed) return;
    _mode = mode;
    switch (mode) {
      case FallMode.off:
        _sensorUnavailable = false;
        await _source.stop();
      case FallMode.shadow:
        final ok = await _source.start();
        // Başlatma sürerken mod değiştiyse eski kararı uygulama.
        if (_mode != FallMode.shadow) {
          await _source.stop();
        } else {
          _sensorUnavailable = !ok;
        }
    }
    // Başlatma sürerken uygulama kapandıysa: dispose'taki durdurma henüz
    // çalışmayan kaynağa denk gelmiş olabilir; sensör açık kalmasın.
    if (_disposed) {
      await _source.stop();
      return;
    }
    notifyListeners();
  }

  void _onEvaluation(FallEvaluation e) {
    // Mod kapalıyken (durdurma ile son paket arasındaki yarış) hiçbir şey yazılmaz.
    if (_disposed || _mode != FallMode.shadow) return;
    if (!e.outcome.reachedImpact) {
      noImpactCount++;
      notifyListeners();
      return;
    }
    unawaited(log.add(e, source: _source.sourceId));
    if (e.outcome == FallOutcome.candidate && _earconEnabled()) {
      _playCandidateEarcon?.call();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    unawaited(_source.stop());
    super.dispose();
  }
}
