import 'dart:async';

import 'package:flutter/foundation.dart';

import '../accessibility/announcement_queue.dart';
import '../accessibility/feedback_hub.dart';
import '../l10n/strings_tr.dart';
import '../permissions/location_access.dart';
import '../platform/location_service.dart';
import 'guidance_engine.dart';
import 'guidance_speech.dart';
import 'route.dart';
import 'route_planner.dart';

/// [NavigationSession.start] sonucu. Başlamadıysa nedeni: çağıran (6c'de
/// `NavigationHandler`) Google Haritalar yedeğine düşüp nedeni söyler.
enum NavigationStart {
  started,

  /// Konum izni yok ve uygulama ön planda değil (ekran kapalı, sesle
  /// başlatma): izin penceresi görünmez ve servis arka planda konum türüyle
  /// başlatılamaz, bu yüzden sormaya çalışmadan yedeğe düşülür.
  permissionNeeded,

  /// Konum izni istendi, verilmedi.
  permissionDenied,

  /// Telefonun konum servisi kapalı.
  locationOff,
}

/// Çalışan bir navigasyon: rota + [GuidanceEngine] + konum kaynağı +
/// duyurular. Motor saf mantıktır; bu sınıf onu gerçek dünyaya (konum akışı,
/// saat, TTS, yeniden rota) bağlar. Akış: konum -> motor -> olay ->
/// [describeEvent] -> [FeedbackHub].
///
/// Güvenlik ilkesi: hiçbir cümle karşıya geçiş kararı içermez; geçiş
/// noktasında motor susar ([GuidanceEngine.isPausedForCrossing]).
class NavigationSession extends ChangeNotifier {
  final FeedbackHub _feedback;
  final PatikaLocationService _location;
  final RoutePlanner? _planner;
  final LocationAccess? _access;
  final bool Function() _isAppVisible;
  final DateTime Function() _now;
  final GuidanceConfig config;
  final Duration tickInterval;

  /// Rota dışındayken yeniden rota hesaplama denemeleri arasındaki en kısa süre.
  final Duration rerouteInterval;

  PatikaLocationService? _source;
  GuidanceEngine? _engine;
  WalkingRoute? _route;
  PositionFix? _lastFix;

  StreamSubscription<PositionFix>? _fixSub;
  StreamSubscription<LocationIssue>? _issueSub;
  Timer? _ticker;

  bool _rerouting = false;
  DateTime? _lastRerouteAt;

  NavigationSession({
    required FeedbackHub feedback,
    required PatikaLocationService location,
    RoutePlanner? planner,
    LocationAccess? access,
    bool Function()? isAppVisible,
    DateTime Function()? now,
    this.config = const GuidanceConfig(),
    this.tickInterval = const Duration(seconds: 1),
    this.rerouteInterval = const Duration(seconds: 30),
  })  : _feedback = feedback,
        _location = location,
        _planner = planner,
        _access = access,
        _isAppVisible = isAppVisible ?? (() => true),
        _now = now ?? DateTime.now;

  bool get active => _engine != null;
  WalkingRoute? get route => _route;
  bool get isPausedForCrossing => _engine?.isPausedForCrossing ?? false;
  bool get isOffRoute => _engine?.isOffRoute ?? false;
  bool get isGpsWeak => _engine?.isGpsWeak ?? false;

  /// Yön teyidi açık mı: rota özetine "yön bilgisi yürümeye başlayınca
  /// gelecek" eklemek için ([describeRouteSummary]'nin `withDirectionNote`'u).
  bool get announcesDirection => config.directionCheck;

  /// "Ne kadar kaldı" cevabı; navigasyon yoksa null.
  String? remainingText() {
    final e = _engine;
    return e == null ? null : describeRemaining(e);
  }

  /// Navigasyonu başlatır. Rota özetini burada söylemiyoruz: onu komutun
  /// sonucu olarak çağıran taraf ([describeRouteSummary]) söyler.
  ///
  /// [location] verilirse (Test Modu simülasyonu) o kaynak kullanılır ve
  /// gerçek konum izni aranmaz.
  Future<NavigationStart> start(WalkingRoute route, {PatikaLocationService? location}) async {
    final source = location ?? _location;
    final access = _access;
    if (location == null && access != null && !await access.isGranted()) {
      if (!_isAppVisible()) return NavigationStart.permissionNeeded;
      if (!await access.requestWithExplanation()) return NavigationStart.permissionDenied;
    }
    if (!await source.isServiceEnabled()) return NavigationStart.locationOff;

    await _teardown();
    _source = source;
    _install(route);
    _fixSub = source.fixes.listen(_onFix);
    _issueSub = source.issues.listen(_onIssue);
    await source.start();
    _ticker = Timer.periodic(tickInterval, (_) => _onTick());
    notifyListeners();
    return NavigationStart.started;
  }

  /// Navigasyonu kapatır (sessiz; söylenecek cümleyi çağıran taraf verir).
  /// Çalışan yoksa false.
  Future<bool> stop() async {
    if (_engine == null) return false;
    await _teardown();
    notifyListeners();
    return true;
  }

  /// Karşıya geçiş bitti ("geçtim", gözlük çift dokunuşu): devam eder. Duraklamış
  /// navigasyon yoksa false.
  bool resumeFromCrossing() {
    final e = _engine;
    if (e == null || !e.isPausedForCrossing) return false;
    _deliver(e.resumeFromCrossing());
    return true;
  }

  /// Kavşak Geçiş Asistanı devreye girdi: navigasyon susar. Açık navigasyon
  /// yoksa false.
  bool pauseForCrossing() {
    final e = _engine;
    if (e == null) return false;
    e.pauseForCrossing(_now());
    notifyListeners();
    return true;
  }

  // -------------------------------------------------------------------------

  void _install(WalkingRoute route) {
    _route = route;
    _engine = GuidanceEngine(route, config: config, startedAt: _now());
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    // Abonelik iptalleri beklenmez: sonuçları önemsiz ve (fake_async'te)
    // tamamlanmıyor; asıl beklenen konum kaynağının durması.
    unawaited(_fixSub?.cancel());
    unawaited(_issueSub?.cancel());
    _fixSub = null;
    _issueSub = null;
    final source = _source;
    _source = null;
    _engine = null;
    _route = null;
    _lastFix = null;
    _rerouting = false;
    _lastRerouteAt = null;
    await source?.stop();
  }

  void _onFix(PositionFix fix) {
    final e = _engine;
    if (e == null) return;
    _lastFix = fix;
    _deliver(e.update(fix));
  }

  void _onTick() {
    final e = _engine;
    if (e == null) return;
    _deliver(e.tick(_now()));
    _maybeReroute();
  }

  void _onIssue(LocationIssue issue) {
    _feedback.say(
      issue == LocationIssue.serviceDisabled ? Tr.navLocationOff : Tr.navLocationDenied,
      priority: AnnouncementPriority.high,
    );
  }

  /// Motor olaylarını sırayla söyler; varışta oturumu kapatır.
  void _deliver(List<GuidanceEvent> events) {
    for (final event in events) {
      _feedback.say(describeEvent(event), priority: _priority(event));
    }
    if (events.any((e) => e is OffRoute)) _maybeReroute();
    if (_engine?.isFinished ?? false) {
      _teardown().then((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  static AnnouncementPriority _priority(GuidanceEvent event) => switch (event) {
        // Kullanıcının hemen bilmesi gerekenler: konuşmayı keser.
        CrossingPoint() ||
        OffRoute() ||
        BackOnRoute() ||
        GpsWeak() ||
        GpsRecovered() =>
          AnnouncementPriority.high,
        // Yol boyu bilgi: açık bir diyalog/okuma varsa sırasını bekler.
        _ => AnnouncementPriority.normal,
      };

  /// Rota dışındayken (ve planlayıcı varsa) yeni rota ister. Denemeler
  /// arasında [rerouteInterval] beklenir; hesaplanamazsa söylenir ve süre
  /// dolunca yeniden denenir. Planlayıcı yoksa yalnızca "rotanın
  /// dışındasınız" denmiş olur (anahtarsız kullanım).
  Future<void> _maybeReroute() async {
    final planner = _planner;
    final engine = _engine;
    final route = _route;
    final from = _lastFix?.position;
    if (planner == null || engine == null || route == null || from == null) return;
    if (!engine.isOffRoute || _rerouting) return;
    final last = _lastRerouteAt;
    if (last != null && _now().difference(last) < rerouteInterval) return;

    _rerouting = true;
    _lastRerouteAt = _now();
    _feedback.say(Tr.navRerouting, priority: AnnouncementPriority.high);
    try {
      final fresh = await planner.plan(
        from: from,
        to: route.end,
        destinationName: route.destinationName,
      );
      if (_engine != engine) return; // bu arada durduruldu ya da değişti
      _install(fresh);
      _feedback.say(Tr.navNewRoute(describeRouteSummary(fresh)),
          priority: AnnouncementPriority.high);
      notifyListeners();
    } catch (e) {
      debugPrint('[Navigation] yeni rota hesaplanamadı: $e');
      if (_engine == engine) {
        _feedback.say(Tr.navRerouteFailed, priority: AnnouncementPriority.high);
      }
    } finally {
      // Başarıda da sıfırlanmalı: yeni motor kurulduğu için `_engine == engine`
      // artık doğru değil. Bayat bir çağrı yenisine zarar vermez, çünkü
      // yukarıda `_engine != engine` ise hiçbir şey kurulmuyor.
      _rerouting = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _fixSub?.cancel();
    _issueSub?.cancel();
    super.dispose();
  }
}
