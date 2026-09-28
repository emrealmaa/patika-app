import 'dart:math' as math;

import 'geo.dart';
import 'route.dart';

/// Motorun kullanıcıya söylenmesini istediği olaylar. Cümleyi kuran
/// `guidance_speech.dart`; motor yalnızca ne olduğunu bildirir.
sealed class GuidanceEvent {
  const GuidanceEvent();
}

/// Bir dönüş yaklaşıyor. [meters] gerçek uzaklık; söylenirken yuvarlanır.
class ManeuverAhead extends GuidanceEvent {
  final Maneuver maneuver;
  final String? streetName;
  final double meters;
  const ManeuverAhead(this.maneuver, this.streetName, this.meters);
}

/// Karşıya geçiş noktası yaklaşıyor.
class CrossingAhead extends GuidanceEvent {
  final double meters;
  const CrossingAhead(this.meters);
}

/// Karşıya geçiş noktasına varıldı: navigasyon **susar** (duraklar), geçiş
/// kararı Kavşak Geçiş Asistanına aittir. Motor bu noktada hiçbir "geç",
/// "güvenli" ya da "yol açık" türü bilgi üretmez.
class CrossingPoint extends GuidanceEvent {
  const CrossingPoint();
}

/// Geçiş bitti (kullanıcı "geçtim" dedi ya da konum geçişin ötesine ilerledi).
class CrossingResumed extends GuidanceEvent {
  const CrossingResumed();
}

/// Duraklama üst süreye ([GuidanceConfig.crossingMaxPause]) takıldı: kullanıcı
/// hiçbir kanaldan devam ettirmedi, navigasyon kendiliğinden devam eder ve
/// bunu söyler. Geçişin bittiğini varsaymaz - konum ilerlemesi olduğu yerde kalır.
class CrossingTimedOut extends GuidanceEvent {
  const CrossingTimedOut();
}

/// Yürüme yönünün rotayla ilişkisi (bkz. [DirectionInfo]).
enum DirectionVerdict {
  /// Hareket yönü rotanın yönüyle uyumlu.
  along,

  /// Rotanın tersi yönünde.
  opposite,

  /// Rotaya yan (ne uyumlu ne ters).
  across,
}

/// Yön teyidi: hareket yönünden (eklentinin `heading`'inden değil, konum
/// geçmişinden) hesaplanır. Yalnızca yeterince yürünmüş, doğruluğu iyi ve
/// yürüme hızında ise verilir; yoksa hiç söylenmez (yanlış yön, hiç
/// söylememekten kötü).
class DirectionInfo extends GuidanceEvent {
  final DirectionVerdict verdict;
  const DirectionInfo(this.verdict);
}

class NearDestination extends GuidanceEvent {
  final double meters;
  const NearDestination(this.meters);
}

class Arrived extends GuidanceEvent {
  const Arrived();
}

class OffRoute extends GuidanceEvent {
  const OffRoute();
}

class BackOnRoute extends GuidanceEvent {
  const BackOnRoute();
}

class GpsWeak extends GuidanceEvent {
  const GpsWeak();
}

class GpsRecovered extends GuidanceEvent {
  const GpsRecovered();
}

/// Konum okuması. [accuracyMeters]: cihazın bildirdiği yatay doğruluk.
class PositionFix {
  final LatLng position;
  final double accuracyMeters;
  final DateTime time;
  const PositionFix(this.position, this.accuracyMeters, this.time);
}

/// Eşikler tek yerde: gerçek kullanıcı ve gerçek GPS ile ayarlanacak
/// (bkz. CLAUDE.md "Bekleyen telefon testleri"), şimdilik varsayım.
class GuidanceConfig {
  /// Dönüşten bu kadar önce ilk, bu kadar önce ikinci duyuru (metre).
  final double farApproach;
  final double nearApproach;

  /// Hedefe bu kadar yaklaşınca "hedef çevresindesiniz".
  final double arrivalRadius;

  /// Rota dışı: rotaya uzaklık `offRouteBase + doğruluk` metreyi ardışık
  /// [offRouteFixes] okuma boyunca aşarsa. Geri dönüş eşiği bilerek daha
  /// dar (`backOnRouteBase + doğruluk`): sınırda gidip gelen konum sürekli
  /// "rotadan çıktınız/döndünüz" dedirtmesin.
  final double offRouteBase;
  final double backOnRouteBase;
  final int offRouteFixes;

  /// Doğruluk [weakAccuracy] metreden kötü olan ardışık [weakFixes] okuma
  /// ya da [staleAfter] süredir okuma yoksa "konum belirsiz". Doğruluk
  /// [goodAccuracy]'ye inince toparlanır (histerezis).
  final double weakAccuracy;
  final double goodAccuracy;
  final int weakFixes;
  final Duration staleAfter;

  /// Geçiş adımının bitişinden bu kadar ileri gidilirse duraklama kendiliğinden biter.
  final double crossingResumeBeyond;

  /// Duraklamanın üst süresi: hiçbir kanaldan (konum, gözlük çift dokunuşu,
  /// "geçtim") devam ettirilmezse navigasyon kendiliğinden devam eder.
  /// Uzun bir kırmızı ışıkta bile sonsuza dek susmasın.
  final Duration crossingMaxPause;

  /// Yön teyidi (bkz. CLAUDE.md Faz 6 kararları, madde 4). Tek satırla
  /// kapatılır: `directionCheck: false`. Aşağıdakiler varsayım, gerçek
  /// yürüyüşte ayarlanacak: en az [directionMinWalk] metre yürünmüş ve bu
  /// mesafe doğruluğun iki katından uzun, her okuma [directionMaxAccuracy]
  /// metreden iyi, [directionWindow] içinde ortalama hız [directionMinSpeed]
  /// m/s üzerinde (yavaşta GPS yönü gürültülü). [directionAlong] dereceden
  /// az sapma "rota yönünde", [directionOpposite]'dan çok "tersi". Rotanın
  /// ilk [directionUntil] metresinde denenir.
  final bool directionCheck;
  final double directionMinWalk;
  final double directionMaxAccuracy;
  final double directionMinSpeed;
  final Duration directionWindow;
  final double directionAlong;
  final double directionOpposite;
  final double directionUntil;

  /// Rotadan bu kadar geride/ileride konum aranır (metre): rota kendine
  /// yakın geri gelirse ("U" biçimli) yanlış parçaya atlamasın.
  final double searchBack;
  final double searchAhead;

  const GuidanceConfig({
    this.farApproach = 50,
    this.nearApproach = 15,
    this.arrivalRadius = 20,
    this.offRouteBase = 20,
    this.backOnRouteBase = 10,
    this.offRouteFixes = 3,
    this.weakAccuracy = 40,
    this.goodAccuracy = 30,
    this.weakFixes = 3,
    this.staleAfter = const Duration(seconds: 15),
    this.crossingResumeBeyond = 25,
    this.crossingMaxPause = const Duration(seconds: 90),
    this.directionCheck = true,
    this.directionMinWalk = 15,
    this.directionMaxAccuracy = 10,
    this.directionMinSpeed = 0.7,
    this.directionWindow = const Duration(seconds: 30),
    this.directionAlong = 45,
    this.directionOpposite = 135,
    this.directionUntil = 100,
    this.searchBack = 25,
    this.searchAhead = 300,
  });
}

class _Segment {
  final LatLng a;
  final LatLng b;
  final double start; // rota boyunca birikimli uzaklık (m)
  final double length;
  const _Segment(this.a, this.b, this.start, this.length);
  double get end => start + length;
}

/// Rota + konum okumaları -> [GuidanceEvent]. Saf mantık: konum eklentisi,
/// saat, TTS bilmez (zaman okumadan gelir) - bu yüzden tümüyle birim
/// testle sınanır.
///
/// İlerleme rota boyunca tek bir sayıdır (`_progress`, metre) ve **yalnızca
/// ileri** gider; böylece bir dönüş iki kez duyurulmaz.
class GuidanceEngine {
  final WalkingRoute route;
  final GuidanceConfig config;

  final List<_Segment> _segments = [];
  final List<double> _stepStart = []; // her adımın rota üzerindeki başlangıcı
  late final double _total;

  double _progress = 0;
  bool _finished = false;

  bool _offRoute = false;
  int _offCount = 0;

  bool _gpsWeak = false;
  int _weakCount = 0;
  DateTime? _lastFixTime;

  // Hedef (adım başlangıcı ya da varış) başına söylenen en yakın aşama:
  // 1 = uzak duyuru, 2 = yakın duyuru.
  final Map<int, int> _stage = {};

  // Duraklama: rotadaki bir geçiş adımı yüzünden ([_pausedStep] dolu) ya da
  // dışarıdan ([pauseForCrossing], adım yok). [_pausedAt] üst süre için.
  bool _paused = false;
  int? _pausedStep;
  DateTime? _pausedAt;
  final Set<int> _crossingDone = {};

  // Yön teyidi: pencere içindeki iyi okumalar (konum + o andaki rota ilerlemesi).
  final List<(PositionFix, double)> _dirSamples = [];
  DirectionVerdict? _dirLast;
  bool _dirDone = false;

  GuidanceEngine(this.route, {this.config = const GuidanceConfig(), DateTime? startedAt})
      : _lastFixTime = startedAt {
    var offset = 0.0;
    LatLng? previousEnd;
    for (var i = 0; i < route.steps.length; i++) {
      final points = route.steps[i].points;
      // Google adımları genelde uç uca biter; boşluk varsa (yuvarlama) bir
      // önceki adıma bağlayıcı parça ekleyip ilerleme sürekliliğini koruruz.
      if (previousEnd != null && distanceMeters(previousEnd, points.first) > 0.5) {
        final gap = distanceMeters(previousEnd, points.first);
        _segments.add(_Segment(previousEnd, points.first, offset, gap));
        offset += gap;
      }
      _stepStart.add(offset);
      for (var j = 1; j < points.length; j++) {
        final len = distanceMeters(points[j - 1], points[j]);
        _segments.add(_Segment(points[j - 1], points[j], offset, len));
        offset += len;
      }
      previousEnd = points.last;
    }
    _total = offset;
  }

  bool get isFinished => _finished;
  bool get isOffRoute => _offRoute;
  bool get isGpsWeak => _gpsWeak;
  bool get isPausedForCrossing => _paused;

  double get remainingMeters => (_total - _progress).clamp(0.0, double.infinity);

  /// Kalan yaklaşık süre: Google'ın toplam süresi kalan yola orantılı bölünür.
  Duration get remainingDuration {
    if (_total <= 0) return Duration.zero;
    return route.duration * (remainingMeters / _total);
  }

  /// Yeni konum okuması. O kareyle ilgili duyuruları döndürür (çoğu zaman boş).
  List<GuidanceEvent> update(PositionFix fix) {
    if (_finished) return const [];
    final events = <GuidanceEvent>[];
    _lastFixTime = fix.time;

    // --- Duraklama üst süresi: konum güvenilmez olsa bile geçerli.
    if (_pauseTimedOut(fix.time)) return _resumeAfterTimeout();

    // --- GPS sağlığı: kötü okumayla konum yargısı verilmez.
    if (fix.accuracyMeters > config.weakAccuracy) {
      _weakCount++;
      if (!_gpsWeak && _weakCount >= config.weakFixes) {
        _gpsWeak = true;
        events.add(const GpsWeak());
      }
      return events;
    }
    _weakCount = 0;
    if (_gpsWeak) {
      if (fix.accuracyMeters > config.goodAccuracy) return events;
      _gpsWeak = false;
      events.add(const GpsRecovered());
    }

    // --- Rotaya izdüşüm (yalnızca ilerinin penceresinde).
    final projection = _project(fix.position);
    final offLimit = config.offRouteBase + fix.accuracyMeters;
    final backLimit = config.backOnRouteBase + fix.accuracyMeters;
    final distance = projection?.distance ?? double.infinity;

    // --- Karşıya geçiş duraklaması: navigasyon susar. Rota dışı denetimi de
    // yapılmaz - kullanıcı Google'ın çizdiği çizgiden başka bir noktadan
    // karşıya geçebilir; ortasında "rotanın dışındasınız" demek de yeniden
    // rota hesaplamak da yanlış olur.
    if (_paused) {
      if (distance <= offLimit) _advance(projection!.progress);
      final step = _pausedStep;
      // Dışarıdan duraklatıldıysa (adım yok) konumla devam edilmez.
      if (step == null || _progress < _stepEnd(step) + config.crossingResumeBeyond) {
        return events;
      }
      events.addAll(resumeFromCrossing());
      _offCount = 0;
      return events;
    }

    if (_offRoute) {
      if (distance <= backLimit) {
        _offRoute = false;
        _offCount = 0;
        events.add(const BackOnRoute());
        _advance(projection!.progress);
      }
      return events;
    }
    if (distance > offLimit) {
      if (++_offCount >= config.offRouteFixes) {
        _offRoute = true;
        events.add(const OffRoute());
      }
      return events;
    }
    _offCount = 0;
    _advance(projection!.progress);

    final direction = _checkDirection(fix);
    if (direction != null) events.add(direction);
    _announceNext(events);
    return events;
  }

  /// Zaman geçişi (okuma gelmese de çağrılmalı): uzun süredir konum yoksa
  /// "konum belirsiz" - sessizlik "her şey yolunda" ile karışmasın.
  List<GuidanceEvent> tick(DateTime now) {
    if (_finished) return const [];
    if (_paused) return _pauseTimedOut(now) ? _resumeAfterTimeout() : const [];
    final last = _lastFixTime;
    if (_gpsWeak || last == null) return const [];
    if (now.difference(last) < config.staleAfter) return const [];
    _gpsWeak = true;
    return const [GpsWeak()];
  }

  /// Navigasyonu dışarıdan duraklatır (Kavşak Geçiş Asistanı devreye girdi):
  /// rotada geçiş adımı yoktur, bu yüzden konumla kendiliğinden devam etmez;
  /// [resumeFromCrossing] ya da üst süre ([GuidanceConfig.crossingMaxPause])
  /// ile çıkar. Zaten duraklıysa süre yeniden başlamaz.
  void pauseForCrossing(DateTime now) {
    if (_finished || _paused) return;
    _pause(null, now);
  }

  /// Kullanıcı karşıya ulaştığını söyledi ("geçtim"), gözlüğe çift dokundu ya da
  /// konum geçişin ötesine ilerledi: navigasyon kaldığı yerden devam eder.
  /// (Dördüncü çıkış kanalı, zaman aşımı, kendiliğinden işler.)
  List<GuidanceEvent> resumeFromCrossing() {
    if (!_paused) return const [];
    final step = _pausedStep;
    _clearPause();
    if (step != null) {
      _crossingDone.add(step);
      _progress = _progress > _stepEnd(step) ? _progress : _stepEnd(step);
    }
    final events = <GuidanceEvent>[const CrossingResumed()];
    // Geçişin hemen ardından gelen dönüş ("rota sola sapıyor") bu an
    // söylenmezse bir sonraki okuma ilerlemeyi dönüşün ötesine iter ve hiç
    // söylenmez; kullanıcı geçişten çıkınca hangi yöne gittiğini bilemez.
    _announceNext(events);
    return events;
  }

  // -------------------------------------------------------------------------

  void _pause(int? step, DateTime? at) {
    _paused = true;
    _pausedStep = step;
    _pausedAt = at ?? _lastFixTime;
  }

  void _clearPause() {
    _paused = false;
    _pausedStep = null;
    _pausedAt = null;
  }

  bool _pauseTimedOut(DateTime now) {
    final since = _pausedAt;
    return _paused && since != null && now.difference(since) >= config.crossingMaxPause;
  }

  /// Üst süre doldu: ilerleme zıplatılmaz (kullanıcı hâlâ geçişin öncesinde
  /// olabilir), yalnızca duraklama biter.
  List<GuidanceEvent> _resumeAfterTimeout() {
    final step = _pausedStep;
    _clearPause();
    if (step != null) _crossingDone.add(step);
    final events = <GuidanceEvent>[const CrossingTimedOut()];
    _announceNext(events);
    return events;
  }

  double _stepEnd(int step) => step + 1 < _stepStart.length ? _stepStart[step + 1] : _total;

  ({double progress, double distance})? _project(LatLng p) {
    ({double progress, double distance})? best;
    for (final s in _segments) {
      if (s.end < _progress - config.searchBack) continue;
      if (s.start > _progress + config.searchAhead) break;
      final r = projectOnSegment(p, s.a, s.b);
      if (best == null || r.distance < best.distance) {
        best = (progress: s.start + r.t * s.length, distance: r.distance);
      }
    }
    return best;
  }

  /// Rota üzerinde [p]. metredeki yürüme yönü (radyan).
  double _routeBearingAt(double p) {
    for (final s in _segments) {
      if (s.length > 0 && s.end >= p) return bearingRadians(s.a, s.b);
    }
    final last = _segments.last;
    return bearingRadians(last.a, last.b);
  }

  /// Yön teyidi: son [GuidanceConfig.directionWindow] içindeki iyi okumalarda
  /// yeterince yürünmüşse hareket yönünü rotayla karşılaştırır. Şartlar
  /// sağlanmazsa null (sessiz). "Rota yönünde" bir kez söylenince iş biter;
  /// "tersi/yan" söylenirse kullanıcı yön değiştirdiğinde farklı bir sonuç
  /// yine söylenir (düzeldiğini duymak için).
  DirectionInfo? _checkDirection(PositionFix fix) {
    if (!config.directionCheck || _dirDone) return null;
    if (_progress > config.directionUntil) {
      _dirDone = true;
      _dirSamples.clear();
      return null;
    }
    if (fix.accuracyMeters > config.directionMaxAccuracy) return null;

    _dirSamples.add((fix, _progress));
    while (_dirSamples.length > 1 &&
        fix.time.difference(_dirSamples.first.$1.time) > config.directionWindow) {
      _dirSamples.removeAt(0);
    }

    final (first, firstProgress) = _dirSamples.first;
    final walked = distanceMeters(first.position, fix.position);
    final needed = math.max(
      config.directionMinWalk,
      2 * math.max(first.accuracyMeters, fix.accuracyMeters),
    );
    if (walked < needed) return null;

    // Yürüme hızı: gerçek yol / süre. Yavaşta (bekleme, oyalanma) GPS yönü
    // güvenilmez; pencere kayarken beklenir.
    final seconds = fix.time.difference(first.time).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    var path = 0.0;
    for (var i = 1; i < _dirSamples.length; i++) {
      path += distanceMeters(_dirSamples[i - 1].$1.position, _dirSamples[i].$1.position);
    }
    if (path / seconds < config.directionMinSpeed) return null;

    // Aralıkta rota köşe aldıysa tek bir "rota yönü" yoktur: pencereyi sıfırla.
    final routeStart = _routeBearingAt(firstProgress);
    final routeEnd = _routeBearingAt(_progress);
    if (angleDifferenceDegrees(routeStart, routeEnd) > 30) {
      _dirSamples
        ..clear()
        ..add((fix, _progress));
      return null;
    }

    final moved = bearingRadians(first.position, fix.position);
    final diff = angleDifferenceDegrees(moved, routeEnd);
    final verdict = diff <= config.directionAlong
        ? DirectionVerdict.along
        : diff >= config.directionOpposite
            ? DirectionVerdict.opposite
            : DirectionVerdict.across;

    _dirSamples.clear(); // sonraki karar yeni bir pencereyle
    if (verdict == _dirLast) return null;
    _dirLast = verdict;
    if (verdict == DirectionVerdict.along) _dirDone = true;
    return DirectionInfo(verdict);
  }

  void _advance(double progress) {
    if (progress > _progress) _progress = progress;
  }

  /// Sıradaki duyurulacak hedefi (dönüş, geçiş noktası ya da varış) bulup
  /// uzaklığa göre aşamasını söyler.
  void _announceNext(List<GuidanceEvent> events) {
    final destination = route.steps.length;

    for (var k = 1; k <= destination; k++) {
      final at = k == destination ? _total : _stepStart[k];
      if (k < destination) {
        final step = route.steps[k];
        if (step.isCrossing) {
          if (_crossingDone.contains(k)) continue;
          if (_progress >= _stepEnd(k) + config.crossingResumeBeyond) {
            // Geçiş adımı bir GPS boşluğunda atlandı; kimseyi duraklatma.
            _crossingDone.add(k);
            continue;
          }
        } else {
          // Düz devam ("straight") gürültüdür (Bilişsel Yük ilkesi); geçilmiş
          // hedef de atlanır. Katı ">" bilerek: "geçtim" sonrası ilerleme tam
          // geçiş adımının bitişine (= sonraki dönüşün başına) oturur ve o
          // dönüş yine de duyurulmalıdır.
          if (step.maneuver == Maneuver.straight || _progress > at) continue;
        }
      }
      final meters = at - _progress;
      _announce(k, destination, meters, events);
      return; // her karede yalnızca en yakın hedef
    }
  }

  void _announce(int k, int destination, double meters, List<GuidanceEvent> events) {
    final stage = _stage[k] ?? 0;

    if (k == destination) {
      if (meters <= config.arrivalRadius) {
        _finished = true;
        events.add(const Arrived());
      } else if (meters <= config.farApproach && stage < 1) {
        _stage[k] = 1;
        events.add(NearDestination(meters));
      }
      return;
    }

    final step = route.steps[k];
    if (step.isCrossing) {
      if (meters <= config.nearApproach || _progress >= _stepStart[k]) {
        _stage[k] = 2;
        _pause(k, null);
        events.add(const CrossingPoint());
      } else if (meters <= config.farApproach && stage < 1) {
        _stage[k] = 1;
        events.add(CrossingAhead(meters));
      }
      return;
    }

    if (meters <= config.nearApproach && stage < 2) {
      _stage[k] = 2;
      events.add(ManeuverAhead(step.maneuver, step.streetName, meters));
    } else if (meters <= config.farApproach && stage < 1) {
      _stage[k] = 1;
      events.add(ManeuverAhead(step.maneuver, step.streetName, meters));
    }
  }
}
