import 'dart:async';

import 'package:flutter/foundation.dart';

import '../navigation/guidance_engine.dart' show PositionFix;
import 'sos_call_monitor.dart';
import 'sos_config.dart';
import 'sos_delivery.dart';

enum SosPhase {
  idle,

  /// Tetiklendi, ön kontrol yapılıyor (çok kısa).
  preparing,

  /// Geri sayım: iptal edilebilir. Varsayılan GÖNDER.
  countdown,

  /// Gönderiliyor: artık iptal edilemez.
  sending,
}

class SosStatus {
  final SosPhase phase;
  final Duration remaining;
  final SosSource? source;

  const SosStatus(this.phase, {this.remaining = Duration.zero, this.source});

  static const idle = SosStatus(SosPhase.idle);
}

enum SosTriggerResult {
  /// Geri sayım başladı.
  started,

  /// Zaten geri sayımda ya da gönderiyor; ikinci tetikleme yok sayıldı.
  alreadyRunning,

  /// Yakın zamanda başarıyla gönderilmişti (sesli olmayan tetikleyiciler).
  rateLimited,

  /// Ön kontrol geçmedi (desteklenmiyor, kişi yok, izin yok); söylendi.
  blocked,
}

/// Konumun SMS'e girip girmediği (kullanıcıya söylenir).
enum SosLocation { included, noPermission, unavailable }

/// SOS'un kullanıcıya söylediği her şey. Metinler ve sesler burada değil,
/// uygulayanda (`FeedbackHub` üzerinden, Faz 7a-2): denetleyici zamanlama ve
/// karar mantığıdır, testte kaydedilen olaylarla denenir.
///
/// **Arama sırasında konuşma yoktur.** `Future<void>` dönenler konuşma
/// BİTİNCE tamamlanır; denetleyici aramayı ancak ondan sonra başlatır.
abstract class SosAnnouncer {
  /// `play` derlemesi: bu sürümde SOS yok.
  void unsupported();

  /// Acil kişi yok. [offer112]: "112'yi aramak için çift dokunun" da söylensin.
  void noContacts({required bool offer112});

  void noSmsPermission({required bool offer112});

  /// Yalnızca 112 aranacaktı ama arama izni yok.
  void noCallPermission();

  /// Yakın zamanda gönderilmiş (60 sn sınırı).
  void rateLimited();

  void countdownStarted(SosSource source, Duration total);

  /// Geri sayımda her saniye (kalan süre). Bip burada çalınır.
  void tick(Duration remaining);

  void cancelled(SosCancelSource by);

  /// Gönderim başlamışken iptal istendi.
  void cancelTooLate();

  /// Gönderim başlıyor.
  void sending(SosLocation location);

  /// SMS sonuçları, arama BAŞLAMADAN. "Gönderildi" yalnızca `sent` olanlar için
  /// söylenir, "iletildi" hiç söylenmez; `pending` olanlar "sonuç bekleniyor".
  /// [callTarget] doluysa sonra o aranacağı söylenir. [offer112] doluysa
  /// "112'yi aramak için çift dokunun" da söylenir ve kısa bir karar süresi
  /// tanınır. Konuşma bitince tamamlanır.
  Future<void> smsResults(
    List<SosRecipientResult> results, {
    required SosLocation location,
    required SosCallTarget callTarget,
    required bool offer112,
  });

  /// Kullanıcı onayıyla 112 aranıyor; ARAMADAN ÖNCE söylenir. Bitince tamamlanır.
  Future<void> calling112();

  /// Onaylı 112 araması yapılamadı.
  void call112Failed(SosCallOutcome outcome);

  /// Arama bittikten (ya da hiç arama yoksa hemen) sonra: geç kalan SMS
  /// sonuçları ([late]) ve/veya başarısız arama. Bitince tamamlanır.
  Future<void> afterCall(SosReport report, {required List<SosRecipientResult> late});

  /// Takip SMS'i sonucu (konum sonradan bulundu). Arama sürerken çağrılmaz.
  void followUp({required bool sent});
}

/// SOS durum makinesi: tetikle → ön kontrol → geri sayım → gönder → sonuç.
///
/// Kurallar (bkz. CLAUDE.md Faz 7 kararları):
/// - Geri sayım süresince iptal yoksa **gönderilir**.
/// - Konum geri sayım BAŞLARKEN aranmaya başlar; bitince varsa kullanılır,
///   yoksa en fazla [SosConfig.locationGrace] beklenir, yine yoksa konumsuz
///   gider ve tek takip SMS'i denenir.
/// - SMS hepsine, sonuçları söylenir, sonra tek arama (112 ayarı açıksa 112,
///   değilse ilk kişi); düşme kaynaklı SOS'ta 112 kendiliğinden hiç aranmaz.
///   Düşmede (ya da hiçbir SMS gitmediyse) SMS sonuçlarından sonra kısa bir
///   pencerede "112'yi aramak için çift dokunun" onaylı teklifi sunulur.
/// - Arama başladıktan sonra uygulama konuşmaz; geç kalan/başarısız sonuçlar
///   arama bitince özetlenir.
/// - 60 sn sınırı yalnızca **başarıyla çıkan** SOS'u sayar ve sesli tetiklemeyi
///   etkilemez.
class SosController {
  final SosDelivery _delivery;
  final SosAnnouncer _announcer;
  final Future<PositionFix?> Function() _getLocation;
  final Future<bool> Function() _hasLocationPermission;
  final bool Function() _call112Enabled;
  final SosCallMonitor _callMonitor;
  final DateTime Function() _now;

  final status = ValueNotifier<SosStatus>(SosStatus.idle);

  SosPhase _phase = SosPhase.idle;
  SosSource? _source;
  Duration _remaining = Duration.zero;
  Timer? _ticker;
  Future<PositionFix?>? _locationFuture;
  bool _locationPermissionMissing = false;
  bool _rateLimited = false;
  Timer? _rateLimitTimer;
  bool _offer112 = false;
  Timer? _offerTimer;
  Completer<SosCallResult?>? _decision;

  /// Bir arama sürerken doludur; bitince tamamlanır. Bu sırada konuşulmaz.
  Completer<void>? _callEnded;
  bool _disposed = false;

  SosController({
    required SosDelivery delivery,
    required SosAnnouncer announcer,
    required Future<PositionFix?> Function() getLocation,
    required Future<bool> Function() hasLocationPermission,
    required bool Function() call112Enabled,
    SosCallMonitor callMonitor = const FixedDelayCallMonitor(),
    DateTime Function()? now,
  })  : _delivery = delivery,
        _announcer = announcer,
        _getLocation = getLocation,
        _hasLocationPermission = hasLocationPermission,
        _call112Enabled = call112Enabled,
        _callMonitor = callMonitor,
        _now = now ?? DateTime.now;

  SosPhase get phase => _phase;

  /// Geri sayım sürüyor mu (iptal edilebilir)?
  bool get inCountdown => _phase == SosPhase.countdown;

  /// Geri sayım ya da gönderim sürüyor mu (yeni tetikleme yok sayılır)?
  bool get busy => _phase != SosPhase.idle;

  /// "112'yi aramak için çift dokunun" teklifi geçerli mi?
  bool get offering112 => _offer112;

  Future<SosTriggerResult> trigger(SosSource source) async {
    if (_phase != SosPhase.idle) return SosTriggerResult.alreadyRunning;
    // Sesli "yardım" her zaman erişilebilir kalır: sınır yalnızca diğerlerine.
    if (_rateLimited && source != SosSource.voice) {
      _announcer.rateLimited();
      return SosTriggerResult.rateLimited;
    }
    _setPhase(SosPhase.preparing, source: source);

    final allow112 = source.may112 && _call112Enabled();
    final SosPreflight pre;
    try {
      pre = await _delivery.preflight(allow112: allow112);
    } catch (e) {
      debugPrint('[SOS] ön kontrol hatası: ${e.runtimeType}');
      // Ön kontrol çökerse SOS sessizce kaybolmasın: geri sayıma geç, gönderim
      // hatası varsa sonuç bunu söyler.
      return _startCountdown(source);
    }
    if (_disposed) return SosTriggerResult.blocked;
    if (pre == SosPreflight.ready) return _startCountdown(source);

    _setPhase(SosPhase.idle);
    switch (pre) {
      case SosPreflight.unsupported:
        _announcer.unsupported();
      // 112 teklifi her kaynakta var: kullanıcı onaylı, kendiliğinden arama değil.
      case SosPreflight.noContacts:
        _announcer.noContacts(offer112: true);
        _open112Offer(SosConfig.offer112Window);
      case SosPreflight.noSmsPermission:
        _announcer.noSmsPermission(offer112: true);
        _open112Offer(SosConfig.offer112Window);
      case SosPreflight.noCallPermission:
        _announcer.noCallPermission();
      case SosPreflight.ready:
        break;
    }
    return SosTriggerResult.blocked;
  }

  /// Geri sayımı iptal eder. Yalnızca geri sayımda mümkündür; gönderim
  /// başladıysa false döner ve bu söylenir.
  bool cancel(SosCancelSource by) {
    if (_phase == SosPhase.countdown) {
      _ticker?.cancel();
      _ticker = null;
      _locationFuture = null;
      _setPhase(SosPhase.idle);
      _announcer.cancelled(by);
      return true;
    }
    if (_phase == SosPhase.sending) {
      _announcer.cancelTooLate();
    }
    return false;
  }

  /// Geri sayımı beklemeden gönderir (ör. geri sayımda "yardım" tekrarı).
  void sendNow() {
    if (_phase == SosPhase.countdown) _send();
  }

  /// "112'yi aramak için çift dokunun" teklifi açıksa 112'yi arar. Teklif
  /// yoksa null (çağıran çift dokunuşu başka işe yorar). Önce "112 aranıyor"
  /// söylenir, ARAMA ondan sonra başlar.
  Future<SosCallOutcome?> confirm112() async {
    if (!_offer112) return null;
    final decision = _decision;
    _close112Offer();
    await _announcer.calling112();
    final outcome = await _delivery.call112();
    if (outcome == SosCallOutcome.placed) {
      _beginCallQuiet();
    } else if (!_disposed) {
      _announcer.call112Failed(outcome);
    }
    if (decision != null && !decision.isCompleted) {
      decision.complete(SosCallResult(outcome, const SosCallTarget(is112: true)));
    }
    return outcome;
  }

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _rateLimitTimer?.cancel();
    _offerTimer?.cancel();
    final decision = _decision;
    if (decision != null && !decision.isCompleted) decision.complete(null);
    status.dispose();
  }

  // --- iç ---------------------------------------------------------------------

  SosTriggerResult _startCountdown(SosSource source) {
    final total = SosConfig.countdownFor(source);
    _remaining = total;
    _setPhase(SosPhase.countdown, source: source);
    _locationPermissionMissing = false;
    _locationFuture = _fetchLocation();
    _announcer.countdownStarted(source, total);

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      _remaining -= const Duration(seconds: 1);
      if (_remaining <= Duration.zero) {
        t.cancel();
        _ticker = null;
        _send();
        return;
      }
      _setPhase(SosPhase.countdown, source: source);
      _announcer.tick(_remaining);
    });
    return SosTriggerResult.started;
  }

  Future<PositionFix?> _fetchLocation() async {
    try {
      if (!await _hasLocationPermission()) {
        _locationPermissionMissing = true;
        return null;
      }
      return await _getLocation();
    } catch (e) {
      debugPrint('[SOS] konum alınamadı: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _send() async {
    final source = _source ?? SosSource.voice;
    final locationFuture = _locationFuture ?? _fetchLocation();
    _ticker?.cancel();
    _ticker = null;
    _setPhase(SosPhase.sending, source: source);

    final fix = await locationFuture.timeout(SosConfig.locationGrace, onTimeout: () => null);
    final location = fix != null
        ? SosLocation.included
        : (_locationPermissionMissing ? SosLocation.noPermission : SosLocation.unavailable);
    if (_disposed) return;
    _announcer.sending(location);

    final allow112 = source.may112 && _call112Enabled();
    final request = SosRequest(source: source, time: _now(), fix: fix, allow112: allow112);

    // 1) SMS'ler başlar; en fazla smsWaitBeforeCall beklenir.
    SosSmsBatch batch;
    SosCallTarget target;
    try {
      batch = await _delivery.startSms(request);
      target = await _delivery.plannedCall(allow112: allow112);
    } catch (e) {
      debugPrint('[SOS] gönderim hatası: ${e.runtimeType}');
      batch = SosSmsBatch(const []);
      target = SosCallTarget.none;
    }
    try {
      await batch.settled.timeout(SosConfig.smsWaitBeforeCall);
    } on TimeoutException {
      // Bitmeyenler `pending` kalır; arama artık beklemez.
    }
    if (_disposed) return;
    final snapshot = batch.results;
    final anySent = snapshot.any((r) => r.sent);

    // 2) Sonuçlar ARAMA BAŞLAMADAN söylenir. Düşmede (ya da hiçbir SMS
    // gitmediyse) 112 için onaylı teklif de sunulur; 112 zaten kendiliğinden
    // aranacaksa teklif gereksiz.
    final offer112 = !target.is112 && (source == SosSource.fall || !anySent);
    await _announcer.smsResults(snapshot, location: location, callTarget: target, offer112: offer112);
    if (_disposed) return;

    // 3) Kısa karar süresi: pencerede çift dokunuş 112'yi onaylar ve kişi aranmaz.
    SosCallResult? call;
    if (offer112) call = await _awaitDecision();
    if (_disposed) return;

    // 4) Tek arama.
    try {
      call ??= await _delivery.placeCall(allow112: allow112);
    } catch (e) {
      debugPrint('[SOS] arama hatası: ${e.runtimeType}');
      call = SosCallResult(SosCallOutcome.failed, target);
    }
    if (call.placed && _callEnded == null) _beginCallQuiet();

    _setPhase(SosPhase.idle);
    if (anySent || call.placed) _startRateLimit();
    if (anySent && location == SosLocation.unavailable) unawaited(_followUpLater());
    unawaited(_afterCall(batch, snapshot, call, location));
  }

  /// Arama bitene kadar susar, geç kalan SMS sonuçlarını bekler, gerekiyorsa
  /// özetler (yalnızca geç kalan ya da başarısız bir şey varsa).
  Future<void> _afterCall(
    SosSmsBatch batch,
    List<SosRecipientResult> snapshot,
    SosCallResult call,
    SosLocation location,
  ) async {
    await _quiet();
    try {
      await batch.settled.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      // Hâlâ bitmeyen `pending` kalır ("sonuç bekleniyor").
    }
    if (_disposed) return;
    final finalResults = batch.results;
    final late = [
      for (var i = 0; i < snapshot.length; i++)
        if (snapshot[i].pending) finalResults[i],
    ];
    final callProblem = call.outcome == SosCallOutcome.failed ||
        call.outcome == SosCallOutcome.noPermission ||
        call.outcome == SosCallOutcome.numberUnavailable;
    if (late.isEmpty && !callProblem) return;
    await _announcer.afterCall(
      SosReport(sms: finalResults, call: call, locationIncluded: location == SosLocation.included),
      late: late,
    );
  }

  /// Konumsuz giden SOS'ta konum yeniden denenir; ilk başarıda TEK takip SMS'i.
  Future<void> _followUpLater() async {
    for (var i = 0; i < SosConfig.followUpAttempts; i++) {
      await Future<void>.delayed(SosConfig.followUpInterval);
      if (_disposed) return;
      final fix = await _fetchLocation();
      if (fix == null) continue;
      final sent = await _delivery.sendFollowUp(time: _now(), fix: fix);
      await _quiet();
      if (!_disposed) _announcer.followUp(sent: sent);
      return;
    }
  }

  /// Bir arama sürüyorsa bitene kadar bekler (o sürece konuşulmaz).
  Future<void> _quiet() => _callEnded?.future ?? Future<void>.value();

  void _beginCallQuiet() {
    final ended = Completer<void>();
    _callEnded = ended;
    unawaited(_callMonitor.untilCallEnds().whenComplete(() {
      if (!ended.isCompleted) ended.complete();
      if (identical(_callEnded, ended)) _callEnded = null;
    }));
  }

  void _startRateLimit() {
    _rateLimited = true;
    _rateLimitTimer?.cancel();
    _rateLimitTimer = Timer(SosConfig.rateLimit, () => _rateLimited = false);
  }

  /// [decision] doluysa süre dolunca null ile tamamlanır (onay gelmedi).
  void _open112Offer(Duration window, [Completer<SosCallResult?>? decision]) {
    _offer112 = true;
    _decision = decision;
    _offerTimer?.cancel();
    _offerTimer = Timer(window, () {
      _offer112 = false;
      final d = _decision;
      _decision = null;
      if (d != null && !d.isCompleted) d.complete(null);
    });
  }

  Future<SosCallResult?> _awaitDecision() {
    final decision = Completer<SosCallResult?>();
    _open112Offer(SosConfig.offerDecisionWindow, decision);
    return decision.future;
  }

  void _close112Offer() {
    _offer112 = false;
    _decision = null;
    _offerTimer?.cancel();
    _offerTimer = null;
  }

  void _setPhase(SosPhase phase, {SosSource? source}) {
    _phase = phase;
    _source = phase == SosPhase.idle ? null : (source ?? _source);
    if (!_disposed) {
      status.value = SosStatus(phase, remaining: _remaining, source: _source);
    }
  }
}
