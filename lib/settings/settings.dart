import '../fall/fall_mode.dart';
import '../l10n/strings_tr.dart';

enum Verbosity { short, long }

enum FeedbackMode { speech, earconOnly }

/// Sesle değiştirilebilen ayar eylemleri ("daha hızlı konuş" vb.). İsimleri
/// AYAR niyetinin entity'si olarak BleCommand üzerinden taşınıyor.
enum SettingAction {
  speechFaster,
  speechSlower,
  shorter,
  longer,
  hapticStronger,
  hapticWeaker,
  hapticOff,
  notificationsMuteOn,
  notificationsMuteOff;

  static SettingAction? fromName(String? name) {
    for (final a in values) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// Kullanıcı ayarları. Değerler serbest sayı değil, sesle "bir kademe
/// artır/azalt" denebilsin ve TalkBack'te kısa bir liste olarak
/// seçilebilsin diye KADEME (index) olarak tutuluyor.
class Settings {
  /// flutter_tts hızları (Android'de 0.5 = normal konuşma hızı).
  static const speechRates = [0.3, 0.4, 0.5, 0.62, 0.75];
  static const pitches = [0.85, 1.0, 1.15];
  static const minSilenceSeconds = 1;
  static const maxSilenceSeconds = 6;
  /// Titreşim genliği çarpanları: kapalı, hafif, orta, güçlü.
  static const hapticScales = [0.0, 0.4, 0.7, 1.0];

  final int speechRateLevel;
  final int pitchLevel;
  final int silenceTimeoutSeconds;
  final Verbosity verbosity;
  final int hapticLevel;

  /// Varsayılan earconOnly: dinleme başlarken "Dinliyorum" sözü yerine
  /// kısa ses çalar (daha hızlı, konuşmayı bölmez).
  final FeedbackMode feedbackMode;

  /// Çift baş sallama dinlemeyi başlatsın mı (yanlış tetiklenebildiği için
  /// varsayılan kapalı).
  final bool nodToListen;

  /// Gelen mesaj bildiriminin içeriği yüksek sesle okunsun mu (Faz 4b).
  /// Varsayılan açık; kapalıyken yalnızca "kimden" söylenir. İlk kez açıkken
  /// okunduğunda bir kerelik sesli gizlilik uyarısı var (bkz. AppState,
  /// LoudMessagesNotice).
  final bool readMessagesAloud;

  /// "Bildirimleri sustur" (Faz 4b) - açıkken gelen mesaj bildirimi hiç
  /// seslendirilmez (yine de günlüğe eklenir, "mesajlarımı oku" ile
  /// okunabilir). Gelen aramayı etkilemez. Varsayılan kapalı.
  final bool notificationsMuted;

  /// Acil durumda (SOS) kişi yerine 112 aransın mı (Faz 7). Varsayılan
  /// KAPALI: asılsız 112 araması idari para cezası gerektirebilir (bkz.
  /// CLAUDE.md Faz 7 kararları). Sesle değil yalnızca ayarlar ekranından
  /// açılır; açılırken sesli uyarı verilir. Düşme kaynaklı SOS bu ayardan
  /// bağımsız olarak 112'yi kendiliğinden aramaz.
  final bool emergencyCall112;

  /// Düşme algılama modu (Faz 7c). null = kullanıcı hiç seçmedi: derleme
  /// türünün varsayılanı geçerli (debug gölge, release kapalı; bkz.
  /// [effectiveFallMode]). Açıkça seçilen değer derleme türünden bağımsız.
  final FallMode? fallMode;

  /// Gölge modunda aday oluşunca kısa test ses işareti çalsın mı. Varsayılan
  /// kapalı (Faz 7c kararı 2): yalnızca deneme sırasında açılır.
  final bool fallShadowEarcon;

  const Settings({
    this.speechRateLevel = 2,
    this.pitchLevel = 1,
    this.silenceTimeoutSeconds = 3,
    this.verbosity = Verbosity.long,
    this.hapticLevel = 2,
    this.feedbackMode = FeedbackMode.earconOnly,
    this.nodToListen = false,
    this.readMessagesAloud = true,
    this.notificationsMuted = false,
    this.emergencyCall112 = false,
    this.fallMode,
    this.fallShadowEarcon = false,
  });

  double get speechRate => speechRates[speechRateLevel];
  double get pitch => pitches[pitchLevel];
  double get hapticScale => hapticScales[hapticLevel];
  Duration get silenceTimeout => Duration(seconds: silenceTimeoutSeconds);

  String get speechRateName => Tr.speechRateNames[speechRateLevel];
  String get pitchName => Tr.pitchNames[pitchLevel];
  String get hapticName => Tr.hapticNames[hapticLevel];
  String get verbosityName =>
      verbosity == Verbosity.short ? Tr.verbosityShort : Tr.verbosityLong;

  Settings copyWith({
    int? speechRateLevel,
    int? pitchLevel,
    int? silenceTimeoutSeconds,
    Verbosity? verbosity,
    int? hapticLevel,
    FeedbackMode? feedbackMode,
    bool? nodToListen,
    bool? readMessagesAloud,
    bool? notificationsMuted,
    bool? emergencyCall112,
    FallMode? fallMode,
    bool? fallShadowEarcon,
  }) {
    return Settings(
      speechRateLevel: _clamp(speechRateLevel ?? this.speechRateLevel, speechRates.length),
      pitchLevel: _clamp(pitchLevel ?? this.pitchLevel, pitches.length),
      silenceTimeoutSeconds: (silenceTimeoutSeconds ?? this.silenceTimeoutSeconds)
          .clamp(minSilenceSeconds, maxSilenceSeconds),
      verbosity: verbosity ?? this.verbosity,
      hapticLevel: _clamp(hapticLevel ?? this.hapticLevel, hapticScales.length),
      feedbackMode: feedbackMode ?? this.feedbackMode,
      nodToListen: nodToListen ?? this.nodToListen,
      readMessagesAloud: readMessagesAloud ?? this.readMessagesAloud,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
      emergencyCall112: emergencyCall112 ?? this.emergencyCall112,
      fallMode: fallMode ?? this.fallMode,
      fallShadowEarcon: fallShadowEarcon ?? this.fallShadowEarcon,
    );
  }

  /// Sesli ayar komutunu uygular. Değer zaten sınırdaysa aynı nesne döner -
  /// çağıran `identical` ile "değişmedi"yi anlayabilir.
  Settings apply(SettingAction action) {
    final next = switch (action) {
      SettingAction.speechFaster => copyWith(speechRateLevel: speechRateLevel + 1),
      SettingAction.speechSlower => copyWith(speechRateLevel: speechRateLevel - 1),
      SettingAction.shorter => copyWith(verbosity: Verbosity.short),
      SettingAction.longer => copyWith(verbosity: Verbosity.long),
      SettingAction.hapticStronger => copyWith(hapticLevel: hapticLevel + 1),
      SettingAction.hapticWeaker => copyWith(hapticLevel: hapticLevel - 1),
      SettingAction.hapticOff => copyWith(hapticLevel: 0),
      SettingAction.notificationsMuteOn => copyWith(notificationsMuted: true),
      SettingAction.notificationsMuteOff => copyWith(notificationsMuted: false),
    };
    return next == this ? this : next;
  }

  Map<String, Object> toJson() => {
        'speechRateLevel': speechRateLevel,
        'pitchLevel': pitchLevel,
        'silenceTimeoutSeconds': silenceTimeoutSeconds,
        'verbosity': verbosity.name,
        'hapticLevel': hapticLevel,
        'feedbackMode': feedbackMode.name,
        'nodToListen': nodToListen,
        'readMessagesAloud': readMessagesAloud,
        'notificationsMuted': notificationsMuted,
        'emergencyCall112': emergencyCall112,
        'fallMode': ?fallMode?.name,
        'fallShadowEarcon': fallShadowEarcon,
      };

  /// Bozuk/eski/eksik alanlar sessizce varsayılana düşer - kayıtlı ayar
  /// dosyası uygulamayı asla açılmaz hale getirmemeli.
  factory Settings.fromJson(Map<String, dynamic> json) {
    const d = Settings();
    int readInt(String key, int fallback) =>
        json[key] is int ? json[key] as int : fallback;
    T readEnum<T extends Enum>(String key, List<T> values, T fallback) =>
        values.firstWhere((v) => v.name == json[key], orElse: () => fallback);

    return d.copyWith(
      speechRateLevel: readInt('speechRateLevel', d.speechRateLevel),
      pitchLevel: readInt('pitchLevel', d.pitchLevel),
      silenceTimeoutSeconds: readInt('silenceTimeoutSeconds', d.silenceTimeoutSeconds),
      verbosity: readEnum('verbosity', Verbosity.values, d.verbosity),
      hapticLevel: readInt('hapticLevel', d.hapticLevel),
      feedbackMode: readEnum('feedbackMode', FeedbackMode.values, d.feedbackMode),
      nodToListen: json['nodToListen'] is bool ? json['nodToListen'] as bool : d.nodToListen,
      readMessagesAloud: json['readMessagesAloud'] is bool
          ? json['readMessagesAloud'] as bool
          : d.readMessagesAloud,
      notificationsMuted: json['notificationsMuted'] is bool
          ? json['notificationsMuted'] as bool
          : d.notificationsMuted,
      emergencyCall112: json['emergencyCall112'] is bool
          ? json['emergencyCall112'] as bool
          : d.emergencyCall112,
      // Tanınmayan değer (ör. ileride eklenecek `on` eski sürümde okunursa)
      // "hiç seçilmedi" sayılır: derleme türü varsayılanı, asla SOS değil.
      fallMode: FallMode.values.asNameMap()[json['fallMode']],
      fallShadowEarcon: json['fallShadowEarcon'] is bool
          ? json['fallShadowEarcon'] as bool
          : d.fallShadowEarcon,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.speechRateLevel == speechRateLevel &&
      other.pitchLevel == pitchLevel &&
      other.silenceTimeoutSeconds == silenceTimeoutSeconds &&
      other.verbosity == verbosity &&
      other.hapticLevel == hapticLevel &&
      other.feedbackMode == feedbackMode &&
      other.nodToListen == nodToListen &&
      other.readMessagesAloud == readMessagesAloud &&
      other.notificationsMuted == notificationsMuted &&
      other.emergencyCall112 == emergencyCall112 &&
      other.fallMode == fallMode &&
      other.fallShadowEarcon == fallShadowEarcon;

  @override
  int get hashCode => Object.hash(speechRateLevel, pitchLevel,
      silenceTimeoutSeconds, verbosity, hapticLevel, feedbackMode, nodToListen,
      readMessagesAloud, notificationsMuted, emergencyCall112, fallMode,
      fallShadowEarcon);

  static int _clamp(int level, int count) => level.clamp(0, count - 1);
}
