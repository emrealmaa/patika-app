import '../../fall/fall_mode.dart';
import '../../l10n/strings_tr.dart';
import '../../sos/sos_controller.dart';
import '../action_result.dart';

/// "Durum" komutunun (Faz 7b) okuduğu anlık bilgi. `AppState` doldurur;
/// testte elle verilir. Bilinmeyen değer null'dır ve uydurulmaz.
class StatusSnapshot {
  final bool glassesConnected;
  final int? glassesBattery;
  final int? phoneBattery;
  final bool phoneCharging;
  final SosPhase sosPhase;
  final bool navigationActive;
  final bool navigationPaused;

  /// "Hedefe 450 metre, yaklaşık 6 dakika kaldı" ("ne kadar kaldı" ile aynı cümle).
  final String? navigationRemaining;

  /// Düşme algılama modu (Faz 7c) ve gölge modunda sensörün açılamadığı.
  final FallMode fallMode;
  final bool fallSensorUnavailable;

  const StatusSnapshot({
    this.glassesConnected = false,
    this.glassesBattery,
    this.phoneBattery,
    this.phoneCharging = false,
    this.sosPhase = SosPhase.idle,
    this.navigationActive = false,
    this.navigationPaused = false,
    this.navigationRemaining,
    this.fallMode = FallMode.off,
    this.fallSensorUnavailable = false,
  });
}

/// DURUM niyeti: gözlük bağlantısı + gözlük pili, telefon pili, çalışan
/// navigasyon; SOS sürüyorsa en başta. Geçmiş SOS özeti YOK (bellekte tutulan
/// geçmiş uygulama kapanınca kaybolur, yanıltıcı olabilir - Faz 7b kararı).
/// Yalnızca okur; hiçbir şeyi değiştirmez.
class StatusHandler {
  final StatusSnapshot Function() _read;

  StatusHandler([StatusSnapshot Function()? read]) : _read = read ?? _unknown;

  static StatusSnapshot _unknown() => const StatusSnapshot();

  Future<ActionResult> handle() async => ActionResult.ok(describeStatus(_read()));
}

/// Özet cümlesi: parçalar ". " ile birleşir, her biri ayrı bir bilgi.
String describeStatus(StatusSnapshot s) {
  final parts = <String>[
    if (s.sosPhase == SosPhase.countdown) Tr.statusSosCountdown,
    if (s.sosPhase == SosPhase.sending) Tr.statusSosSending,
    if (!s.glassesConnected)
      Tr.statusGlassesDisconnected
    else if (s.glassesBattery case final g?)
      Tr.statusGlassesBattery(g)
    else
      Tr.statusGlassesNoBattery,
    if (s.phoneBattery case final p?)
      s.phoneCharging ? Tr.statusPhoneCharging(p) : Tr.statusPhoneBattery(p)
    else
      Tr.statusPhoneUnknown,
    if (!s.navigationActive)
      Tr.statusNavNone
    else if (s.navigationPaused)
      Tr.statusNavPaused
    else ...[
      Tr.statusNavRunning,
      ?s.navigationRemaining,
    ],
    // Yalnızca mod kapalı değilse (Faz 7c kararı 2).
    if (s.fallMode == FallMode.shadow)
      s.fallSensorUnavailable ? Tr.statusFallShadowNoSensor : Tr.statusFallShadow
    else if (s.fallMode == FallMode.on)
      s.fallSensorUnavailable ? Tr.statusFallOnNoSensor : Tr.statusFallOn,
  ];
  return parts.join('. ');
}
