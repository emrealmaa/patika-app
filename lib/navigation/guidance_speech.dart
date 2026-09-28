import '../l10n/strings_tr.dart';
import 'guidance_engine.dart';
import 'route.dart';

/// Mesafeyi söylenebilir hale getirir. Yürüyüşte "47 metre" sahte bir
/// kesinlik (GPS 5-15 m şaşar): yakında 5'e, ortada 10'a, uzakta 50'ye,
/// 1 km'den sonra 100 metreye (bir ondalıklı kilometre) yuvarlanır.
String formatDistance(double meters) {
  final m = meters < 0 ? 0.0 : meters;
  final int rounded;
  if (m < 30) {
    final r = (m / 5).round() * 5;
    rounded = r < 5 ? 5 : r;
  } else if (m < 100) {
    rounded = (m / 10).round() * 10;
  } else {
    rounded = (m / 50).round() * 50;
  }
  if (rounded < 1000) return Tr.navMeters(rounded);

  final tenths = (m / 100).round(); // 12 -> 1,2 km
  final whole = tenths ~/ 10, frac = tenths % 10;
  return Tr.navKilometers(frac == 0 ? '$whole' : '$whole,$frac');
}

/// Süreyi söylenebilir hale getirir ("yaklaşık 15 dakika").
String formatDuration(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 1) return Tr.navUnderMinute;
  if (minutes < 60) return Tr.navAboutMinutes(minutes);
  return Tr.navAboutHours(minutes ~/ 60, minutes % 60);
}

String _turn(Maneuver m) => switch (m) {
      Maneuver.left => Tr.navTurnLeft,
      Maneuver.slightLeft => Tr.navTurnSlightLeft,
      Maneuver.sharpLeft => Tr.navTurnSharpLeft,
      Maneuver.right => Tr.navTurnRight,
      Maneuver.slightRight => Tr.navTurnSlightRight,
      Maneuver.sharpRight => Tr.navTurnSharpRight,
      Maneuver.uTurn => Tr.navTurnUTurn,
      Maneuver.straight || Maneuver.other => Tr.navTurnOther,
    };

/// Motor olayının söylenecek cümlesi. Google'ın kendi talimat metni hiç
/// kullanılmaz: yalnızca manevra türü, mesafe ve sokak adı alınır.
String describeEvent(GuidanceEvent event) => switch (event) {
      ManeuverAhead e when e.meters < 5 => Tr.navManeuverNow(_turn(e.maneuver), e.streetName),
      ManeuverAhead e => Tr.navManeuverAhead(formatDistance(e.meters), _turn(e.maneuver), e.streetName),
      CrossingAhead e => Tr.navCrossingAhead(formatDistance(e.meters)),
      CrossingPoint() => Tr.navCrossingPoint,
      CrossingResumed() => Tr.navCrossingResumed,
      CrossingTimedOut() => Tr.navCrossingTimedOut,
      DirectionInfo e => switch (e.verdict) {
          DirectionVerdict.along => Tr.navDirectionAlong,
          DirectionVerdict.opposite => Tr.navDirectionOpposite,
          DirectionVerdict.across => Tr.navDirectionAcross,
        },
      NearDestination e => Tr.navNearDestination(formatDistance(e.meters)),
      Arrived() => Tr.navArrived,
      OffRoute() => Tr.navOffRoute,
      BackOnRoute() => Tr.navBackOnRoute,
      GpsWeak() => Tr.navGpsWeak,
      GpsRecovered() => Tr.navGpsRecovered,
    };

/// Rota başlarken söylenen özet: "Kadıköy İskelesi, 1,2 kilometre, yaklaşık
/// 15 dakika. Rota Moda Caddesi boyunca 200 metre".
///
/// [withDirectionNote]: yön teyidi açıksa sonuna "Yön bilgisi yürümeye
/// başlayınca gelecek" eklenir - yürümeye başlayana dek yön hakkında sessiz
/// kalınması "her şey yolunda" gibi anlaşılmasın (bkz. `NavigationSession.announcesDirection`).
String describeRouteSummary(WalkingRoute route, {bool withDirectionNote = false}) {
  var text = Tr.navSummary(
    route.destinationName,
    formatDistance(route.lengthMeters),
    formatDuration(route.duration),
  );
  final first = route.steps.first;
  final street = first.streetName;
  if (street != null && street.isNotEmpty) {
    text += '. ${Tr.navFirstStreet(street, formatDistance(first.lengthMeters))}';
  }
  if (withDirectionNote) text += '. ${Tr.navDirectionNote}';
  return text;
}

/// "Ne kadar kaldı" cevabı.
String describeRemaining(GuidanceEngine engine) =>
    Tr.navRemaining(formatDistance(engine.remainingMeters), formatDuration(engine.remainingDuration));
