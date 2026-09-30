import 'dart:async';

import 'package:flutter/foundation.dart';

import '../fall/fall_act.dart';
import '../fall/fall_candidate_source.dart';
import '../fall/fall_mode.dart';
import '../fall/fall_monitor.dart';
import 'sos_config.dart';
import 'sos_controller.dart';

/// Düşme adayını acil durum akışına bağlayan **tek** yer (Faz 7c-2, karar 5).
/// `lib/fall/` SOS'u hiç bilmez; `SosSource.fall` ile tetikleme yalnızca bu
/// dosyada yapılır (kaynak taramasıyla kilitli).
///
/// Bir aday geldiğinde, sırayla:
/// 1. **Sentetik kaynak** (Test Modu düğmeleri) asla eyleme dönmez (karar 11).
/// 2. Mod `on` değilse ya da açık mod **silahlı** değilse ([armed]: kapılar bu
///    oturumda doğrulandı) hiçbir şey yapılmaz. Ayar dosyasındaki `on` tek
///    başına yetmez.
/// 3. **Bastırma** (karar 7): düşme kaynaklı bir SOS iptal edildiyse, iptal
///    anından [suppressionAfterCancel] boyunca yeni aday SOS başlatmaz
///    (`suppressed`); bellekte tutulur. Elle SOS (sesli, gözlük) etkilenmez.
/// 4. Bir SOS zaten sürüyorsa (geri sayım, gönderim, SOS'un araması): yeni aday
///    onu **kesmez** ve ikinci bir SOS başlatmaz (karar 8).
/// 5. **Sıradan** diyalog/dinleme süriyorsa kesilir ([interruptOrdinary]), sonra
///    `trigger(SosSource.fall)`: 25 sn geri sayım, 112 kendiliğinden aranmaz
///    (bunlar `SosController`'da).
///
/// Sonuçlar [onAct] ile bildirilir (kayıt etiketi için); SOS'un sonu
/// [onSosOutcome] ile gelir.
class FallSosBridge {
  /// Düşme kaynaklı SOS iptal edilince yeni adayın bastırıldığı süre.
  static const suppressionAfterCancel = Duration(minutes: 2);

  final SosController _sos;
  final FallMode Function() _mode;
  final bool Function() _armed;
  final Future<void> Function() _interruptOrdinary;
  final void Function(FallCandidate candidate, FallAct act)? _onAct;
  final DateTime Function() _now;

  StreamSubscription<FallCandidate>? _sub;
  DateTime? _suppressedUntil;

  /// Şu an süren düşme kaynaklı SOS'u başlatan aday.
  FallCandidate? _active;
  bool _disposed = false;

  FallSosBridge({
    required Stream<FallCandidate> candidates,
    required SosController sos,
    required FallMode Function() mode,
    required bool Function() armed,
    required Future<void> Function() interruptOrdinary,
    void Function(FallCandidate candidate, FallAct act)? onAct,
    DateTime Function()? now,
  })  : _sos = sos,
        _mode = mode,
        _armed = armed,
        _interruptOrdinary = interruptOrdinary,
        _onAct = onAct,
        _now = now ?? DateTime.now {
    _sub = candidates.listen((c) => unawaited(_onCandidate(c)));
  }

  /// Bastırma sürüyor mu? (Test ve durum için.)
  bool get suppressing {
    final until = _suppressedUntil;
    return until != null && _now().isBefore(until);
  }

  Future<void> _onCandidate(FallCandidate candidate) async {
    if (_disposed) return;
    // 1) Sentetik kaynak: hiçbir koşulda gerçek eyleme dönmez.
    if (candidate.source == fallSyntheticSourceId) return;
    // 2) Açık mod değilse ya da silahlı değilse: hiçbir şey.
    if (_mode() != FallMode.on || !_armed()) return;

    // 3) Bastırma.
    if (suppressing) return _report(candidate, FallAct.suppressed);
    // 4) Zaten bir SOS sürüyor (aramasıyla birlikte): kesme, ikinciyi başlatma.
    if (_busy) return _report(candidate, FallAct.suppressed);

    // 5) Sıradan diyalog/dinleme kesilir, sonra geri sayım.
    try {
      await _interruptOrdinary();
    } catch (e) {
      debugPrint('[Düşme] diyalog kesilemedi: ${e.runtimeType}');
    }
    // Kesme sürerken durum değişmiş olabilir: yeniden doğrula.
    if (_disposed || _mode() != FallMode.on || !_armed()) return;
    if (_busy) return _report(candidate, FallAct.suppressed);

    _active = candidate;
    final SosTriggerResult result;
    try {
      result = await _sos.trigger(SosSource.fall);
    } catch (e) {
      debugPrint('[Düşme] tetikleme hatası: ${e.runtimeType}');
      _active = null;
      return _report(candidate, FallAct.suppressed);
    }
    if (result == SosTriggerResult.started) {
      _report(candidate, FallAct.started);
    } else {
      // Sınır, zaten çalışıyor ya da ön kontrolde takıldı: SOS başlamadı.
      _active = null;
      _report(candidate, FallAct.suppressed);
    }
  }

  bool get _busy => _sos.busy || _sos.callInProgress;

  /// `SosController.onOutcome` buraya bağlanır. Yalnızca düşme kaynaklı
  /// SOS'lar ilgilendirir; elle SOS'un sonu ne bastırır ne etiketler.
  void onSosOutcome(SosSource source, SosOutcome outcome) {
    if (source != SosSource.fall) return;
    final candidate = _active;
    _active = null;
    switch (outcome) {
      case SosOutcome.cancelled:
        // Bastırma iptal anından başlar (karar 7).
        _suppressedUntil = _now().add(suppressionAfterCancel);
        if (candidate != null) _report(candidate, FallAct.cancelled);
      case SosOutcome.sent:
        if (candidate != null) _report(candidate, FallAct.sent);
      case SosOutcome.failed:
        // Gönderim denendi ama çıkmadı: etiket `started` olarak kalır.
        break;
    }
  }

  void _report(FallCandidate candidate, FallAct act) {
    try {
      _onAct?.call(candidate, act);
    } catch (e) {
      debugPrint('[Düşme] etiket bildirimi hatası: ${e.runtimeType}');
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
  }
}
