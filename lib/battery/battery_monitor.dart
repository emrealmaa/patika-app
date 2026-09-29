/// Pil uyarılarının saf mantığı (Faz 7b): eşikler, tekrar önleme, şarj olayları.
/// Flutter'a bağımlı değil; konuşma, titreşim ve "meşgul" kuralı `AppState`'te.
///
/// **Yalnızca uyarır.** Bu sınıf SOS'a, navigasyona ya da arka plan servisine
/// hiçbir şekilde dokunmaz: kritik pilde bile sistem kendi kendine "yardım
/// etmeyi keseyim" kararı vermez (bkz. CLAUDE.md Faz 7b kararları).
library;

/// Pil bilgisinin geldiği yer.
enum BatterySource { glasses, phone }

enum BatteryAlertKind {
  /// Bir eşiğin altına inildi (kritik olmayan).
  low,

  /// En düşük (kritik) eşiğin altına inildi.
  critical,

  /// Kritik seviyede süren hatırlatma: yalnızca titreşim, ses yok.
  reminder,

  /// Telefon şarja takıldı. En düşük öncelik.
  chargeStarted,

  /// Telefon şarjı doldu. En düşük öncelik.
  chargeFull,
}

class BatteryAlert {
  final BatterySource source;
  final BatteryAlertKind kind;
  final int percent;

  const BatteryAlert(this.source, this.kind, this.percent);

  /// Şarj olayları bilgi amaçlıdır; bayat kalırsa okunmaz.
  bool get isChargeEvent =>
      kind == BatteryAlertKind.chargeStarted || kind == BatteryAlertKind.chargeFull;

  @override
  String toString() => 'BatteryAlert($source, $kind, %$percent)';
}

/// Bir kaynağın uyarı eşikleri (azalan sırada) ve geri kurulma payı.
class BatteryThresholds {
  /// Azalan sırada yüzdeler; sonuncusu kritik eşiktir.
  final List<int> levels;

  /// Bir eşik konuşulduktan sonra yeniden uyarabilmesi için pilin o eşiğin
  /// bu kadar puan üstüne çıkması gerekir. Gözlük her %1'de haber verdiği için
  /// eşik civarında dalgalanan pil tekrar tekrar konuşmasın.
  final int hysteresis;

  const BatteryThresholds(this.levels, {this.hysteresis = 5});

  int get critical => levels.last;

  /// Telefon: SOS ve navigasyon buna bağlı, erken uyarı.
  static const phone = BatteryThresholds([30, 15, 5]);

  /// Gözlük.
  static const glasses = BatteryThresholds([20, 10, 5]);

  /// [percent]'i kapsayan en düşük eşik (en ağır olanı); üstünde kalıyorsa null.
  int? applicable(int percent) {
    for (final level in levels.reversed) {
      if (percent <= level) return level;
    }
    return null;
  }
}

class _SourceState {
  /// Şimdiye kadar konuşulan en ağır eşik (null: hiç konuşulmadı / geri kuruldu).
  int? spoken;
  DateTime? lastCriticalAt;
  bool? charging;
  bool fullAnnounced = false;
  bool seen = false;
}

class BatteryMonitor {
  final Map<BatterySource, BatteryThresholds> thresholds;
  final Duration reminderInterval;
  final DateTime Function() _now;
  final Map<BatterySource, _SourceState> _state = {
    for (final s in BatterySource.values) s: _SourceState(),
  };

  BatteryMonitor({
    this.thresholds = const {
      BatterySource.phone: BatteryThresholds.phone,
      BatterySource.glasses: BatteryThresholds.glasses,
    },
    this.reminderInterval = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Bir kaynağın durumunu unutur (gözlük bağlantısı koptu).
  void reset(BatterySource source) => _state[source] = _SourceState();

  /// Yeni okuma. Söylenmesi/çalınması gereken bir şey varsa döner, yoksa null.
  /// [charging]: bilinmiyorsa (gözlük) null; şarj olayları üretilmez.
  BatteryAlert? update(BatterySource source, int percent, {bool? charging}) {
    final st = _state[source]!;
    final thr = thresholds[source]!;
    final previousCharging = st.charging;
    final firstReading = !st.seen;
    st.seen = true;
    st.charging = charging;

    if (charging == true) {
      // Şarjdayken düşük pil uyarısı yok; çıkarılınca eşikler yeniden geçerli.
      st.spoken = null;
      st.lastCriticalAt = null;
      if (firstReading) {
        // Uygulama zaten şarjdayken açıldı: "takıldı/doldu" diye haber verilmez.
        st.fullAnnounced = percent >= 100;
        return null;
      }
      if (percent >= 100 && !st.fullAnnounced) {
        st.fullAnnounced = true;
        return BatteryAlert(source, BatteryAlertKind.chargeFull, percent);
      }
      if (previousCharging == false) {
        st.fullAnnounced = percent >= 100;
        return BatteryAlert(source, BatteryAlertKind.chargeStarted, percent);
      }
      return null;
    }
    st.fullAnnounced = false;

    // Pil eşiğin yeterince üstüne çıktıysa eşikler yeniden kurulur.
    var spoken = st.spoken;
    final applicable = thr.applicable(percent);
    if (spoken != null && percent >= spoken + thr.hysteresis) {
      st.spoken = spoken = applicable;
    }
    if (applicable == null) {
      st.lastCriticalAt = null;
      return null;
    }

    if (spoken == null || applicable < spoken) {
      st.spoken = applicable;
      if (applicable == thr.critical) {
        st.lastCriticalAt = _now();
        return BatteryAlert(source, BatteryAlertKind.critical, percent);
      }
      return BatteryAlert(source, BatteryAlertKind.low, percent);
    }

    final last = st.lastCriticalAt;
    if (applicable == thr.critical && last != null && _now().difference(last) >= reminderInterval) {
      st.lastCriticalAt = _now();
      return BatteryAlert(source, BatteryAlertKind.reminder, percent);
    }
    return null;
  }
}
