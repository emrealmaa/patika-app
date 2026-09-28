import 'package:flutter/foundation.dart';

import '../commands/action_result.dart';
import '../l10n/strings_tr.dart';
import 'geo.dart';
import 'guidance_engine.dart' show PositionFix;
import 'guidance_speech.dart';
import 'navigation_session.dart';
import 'place_search.dart';
import 'route.dart';
import 'route_planner.dart';

/// Söylenen bir yer. [location] yalnızca gerçek modda (Places çözdüyse) dolu;
/// yedek akışta yalnızca söylenen ad var ve Google Haritalar çözer.
class NavPlace {
  final String name;
  final LatLng? location;
  const NavPlace(this.name, [this.location]);
}

/// [NavigationBackend.resolve] sonucu. [places] boşsa yer bulunamadı.
/// [origin] yalnızca gerçek modda dolu (rotanın kalkış noktası); [notice]
/// gerçek moda geçilemediyse nedeni ("Konum izni yok..."), yedek akışta
/// onay sorusundan önce söylenir.
class NavResolution {
  final List<NavPlace> places;
  final PositionFix? origin;
  final String? notice;
  const NavResolution(this.places, {this.origin, this.notice});

  bool get isReal => origin != null;
}

/// Onay sorusu ve başlatma için hazırlanmış navigasyon. [route] doluysa
/// uygulama içi navigasyon, boşsa Google Haritalar yedeği.
class NavPreview {
  final NavPlace place;
  final WalkingRoute? route;
  final String prompt;
  const NavPreview(this.place, this.prompt, {this.route});
}

/// `NavigationFlow`'un konuştuğu arka uç: yeri çöz -> (rotayı hesapla,
/// onay cümlesini üret) -> başlat. İki uygulaması tek sınıfta:
///
/// - **Gerçek** (Google anahtarı var, konum izni/servisi/anlık konum tamam):
///   Places ile yer, Routes ile rota, [NavigationSession] ile navigasyon.
/// - **Yedek** (anahtar yok ya da herhangi bir adım başarısız): söylenen ad
///   Google Haritalar yürüyüş yönlendirmesine verilir. Anahtar yoksa sessizce;
///   başka bir nedenle düştüyse nedeni söylenir.
class NavigationBackend {
  final NavigationSession _session;
  final RoutePlanner? _planner;
  final PlaceSearch? _places;
  final Future<bool> Function(Uri uri) _openMaps;

  NavigationBackend({
    required NavigationSession session,
    RoutePlanner? planner,
    PlaceSearch? places,
    required Future<bool> Function(Uri uri) openMaps,
  })  : _session = session,
        _planner = planner,
        _places = places,
        _openMaps = openMaps;

  /// Google anahtarıyla çalışan tam mod kurulu mu?
  bool get hasApi => _planner != null && _places != null;

  Future<NavResolution> resolve(String spoken) async {
    if (!hasApi) return NavResolution([NavPlace(spoken)]);

    final prepare = await _session.prepare();
    final notice = switch (prepare.status) {
      NavigationPrepareStatus.ready => null,
      NavigationPrepareStatus.permissionNeeded => Tr.navNoticePermissionNeeded,
      NavigationPrepareStatus.permissionDenied => Tr.navNoticePermissionDenied,
      NavigationPrepareStatus.locationOff => Tr.navLocationOff,
      NavigationPrepareStatus.noFix => Tr.navNoticeNoFix,
    };
    final fix = prepare.fix;
    if (notice != null || fix == null) {
      return NavResolution([NavPlace(spoken)], notice: notice);
    }

    try {
      final found = await _places!.search(spoken, near: fix.position);
      return NavResolution(
        [for (final p in found) NavPlace(p.name, p.location)],
        origin: fix,
      );
    } on PlaceSearchException catch (e) {
      debugPrint('[Navigation] yer araması başarısız: $e');
      return NavResolution([NavPlace(spoken)], notice: Tr.navNoticeSearchFailed);
    }
  }

  Future<NavPreview> preview(NavPlace place, NavResolution resolution) async {
    final origin = resolution.origin;
    final target = place.location;
    var notice = resolution.notice;

    if (origin != null && target != null) {
      try {
        final route = await _planner!.plan(
          from: origin.position,
          to: target,
          destinationName: place.name,
        );
        return NavPreview(place, Tr.navConfirmStart(describeRouteSummary(route)), route: route);
      } on RoutePlanException catch (e) {
        debugPrint('[Navigation] rota hesaplanamadı: $e');
        notice = Tr.navNoticeRouteFailed;
      }
    }
    return NavPreview(place, _mapsPrompt(place, notice));
  }

  Future<ActionResult> start(NavPreview preview) async {
    final route = preview.route;
    if (route == null) return _startMaps(preview.place, null);

    final result = await _session.start(route);
    if (result == NavigationStart.started) {
      return ActionResult.ok(
        _session.announcesDirection
            ? '${Tr.navStartedReal}. ${Tr.navDirectionNote}'
            : Tr.navStartedReal,
      );
    }
    // Onay ile başlatma arasında durum değişti (izin geri alındı, konum kapandı).
    final reason = switch (result) {
      NavigationStart.permissionNeeded => Tr.navNoticePermissionNeeded,
      NavigationStart.permissionDenied => Tr.navNoticePermissionDenied,
      _ => Tr.navLocationOff,
    };
    return _startMaps(preview.place, reason);
  }

  String _mapsPrompt(NavPlace place, String? notice) {
    final question = Tr.navConfirmMaps(place.name);
    return notice == null ? question : '$notice. $question';
  }

  Future<ActionResult> _startMaps(NavPlace place, String? reason) async {
    final target = place.location;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': target == null ? place.name : '${target.lat},${target.lng}',
      'travelmode': 'walking',
    });
    if (!await _openMaps(uri)) return ActionResult.fail(Tr.mapsFailed);
    final started = Tr.navStarted(place.name);
    return ActionResult.ok(reason == null ? started : '$reason. $started',
        detail: Tr.navStartedDetail);
  }
}
