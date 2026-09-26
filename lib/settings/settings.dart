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
  hapticOff;

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
  final FeedbackMode feedbackMode;

  const Settings({
    this.speechRateLevel = 2,
    this.pitchLevel = 1,
    this.silenceTimeoutSeconds = 3,
    this.verbosity = Verbosity.long,
    this.hapticLevel = 2,
    this.feedbackMode = FeedbackMode.speech,
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
  }) {
    return Settings(
      speechRateLevel: _clamp(speechRateLevel ?? this.speechRateLevel, speechRates.length),
      pitchLevel: _clamp(pitchLevel ?? this.pitchLevel, pitches.length),
      silenceTimeoutSeconds: (silenceTimeoutSeconds ?? this.silenceTimeoutSeconds)
          .clamp(minSilenceSeconds, maxSilenceSeconds),
      verbosity: verbosity ?? this.verbosity,
      hapticLevel: _clamp(hapticLevel ?? this.hapticLevel, hapticScales.length),
      feedbackMode: feedbackMode ?? this.feedbackMode,
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
      other.feedbackMode == feedbackMode;

  @override
  int get hashCode => Object.hash(speechRateLevel, pitchLevel,
      silenceTimeoutSeconds, verbosity, hapticLevel, feedbackMode);

  static int _clamp(int level, int count) => level.clamp(0, count - 1);
}
