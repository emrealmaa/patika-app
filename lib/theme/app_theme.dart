import 'package:flutter/material.dart';

/// Uygulamanın TÜM renk ve ölçüleri. Ekranlar ve widget'lar renk/ölçü
/// sabiti yazmaz, buradan okur.
///
/// Açık zemin, indigo ana renk. Hedef **WCAG AAA**: her gerçek metin/zemin
/// çifti en az 7:1 ([textPairs], `test/theme_contrast_test.dart` ölçer).
/// Tasarım taslağındaki bazı renkler bu yüzden koyulaştırıldı (ton aynı,
/// yalnızca açıklık düşük):
/// - ikincil metin `#565B82` → `#454A72`
/// - ana/bağlantı rengi `#4338CA`/`#3F42C8` → tek renk `#3538BB`
/// - başarı yazısı `#0B6B4B` → `#0A5D41`
/// - SOS/uyarı `#B4232F` → `#941D27`
/// - gradyan `#5B5FEF → #4338CA` → `#4740CC → #3730A3`; üstündeki tüm yazı
///   beyaz (taslaktaki açık mor ikincil yazı gradyanın hiçbir yerinde 7:1'e
///   ulaşmıyor; hiyerarşi yazı ağırlığı ve boyutuyla kuruluyor).
///
/// Durum renkleri (nokta, ikon) yalnızca yardımcı işarettir: hiçbir durum
/// yalnızca renkle anlatılmaz, her zaman yazıyla da verilir. Renkli
/// noktalar ve anahtar izi metin değil grafik öğe: WCAG 1.4.11'e göre en az
/// 3:1 ([graphicPairs]).
class PatikaTokens {
  PatikaTokens._();

  // --- Zeminler -------------------------------------------------------------
  static const background = Color(0xFFF4F5FB);
  static const card = Color(0xFFFFFFFF);

  /// Açık indigo yüzey: seçili sekme hapı, ikon kutusu, etiket hapı.
  static const primarySoft = Color(0xFFE9EBFF);
  static const divider = Color(0xFFECEEFA);

  // --- Metin ----------------------------------------------------------------
  static const textPrimary = Color(0xFF1E1F4B);
  static const textSecondary = Color(0xFF454A72);

  // --- Ana renk ---------------------------------------------------------------
  /// Hem dolgu (üstünde beyaz yazı) hem açık zeminde yazı/bağlantı rengi.
  static const primary = Color(0xFF3538BB);
  static const onPrimary = Color(0xFFFFFFFF);
  static const heroGradientStart = Color(0xFF4740CC);
  static const heroGradientEnd = Color(0xFF3730A3);
  static const onHero = Color(0xFFFFFFFF);

  /// Vurgu: birincil eylem düğmesi (ör. "Tara"). Üstündeki yazı koyu.
  static const accent = Color(0xFF38C6F4);
  static const onAccent = Color(0xFF0B1B4A);

  // --- Durum ------------------------------------------------------------------
  static const successText = Color(0xFF0A5D41);
  static const successDot = Color(0xFF0E9F6E);
  static const sos = Color(0xFF941D27);
  static const onSos = Color(0xFFFFFFFF);
  static const sosSurface = Color(0xFFFFE6EA);

  /// "Bağlı değil" gibi nötr durum noktası.
  static const neutralDot = Color(0xFF6B7099);

  /// Kapalı anahtar izi (grafik öğe).
  static const switchTrackOff = Color(0xFF8A8FB5);

  // --- SOS tam ekranı (koyu) ----------------------------------------------------
  static const sosBackground = Color(0xFF16154A);
  static const onSosBackground = Color(0xFFFFFFFF);
  static const onSosBackgroundMuted = Color(0xFFD5D6FF);
  static const sosWarningText = Color(0xFFFFD9A8);

  /// Geri sayım halkası (grafik öğe).
  static const sosRing = Color(0xFF38C6F4);
  static const sosRingTrack = Color(0x24FFFFFF);

  // --- Gölge ------------------------------------------------------------------
  static const cardShadow = [
    BoxShadow(color: Color(0x175054C8), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const heroShadow = [
    BoxShadow(color: Color(0x593730A3), blurRadius: 36, offset: Offset(0, 16)),
  ];
  static const navShadow = [
    BoxShadow(color: Color(0x1A5054C8), blurRadius: 30, offset: Offset(0, -10)),
  ];

  // --- Köşe yarıçapları -----------------------------------------------------------
  static const radiusCard = 22.0;
  static const radiusHero = 28.0;
  static const radiusButton = 20.0;
  static const radiusPill = 999.0;
  static const radiusNav = 26.0;
  static const radiusIconBox = 12.0;

  // --- Boşluk -------------------------------------------------------------------
  static const gap = 16.0;
  static const gapSmall = 8.0;
  static const screenPadding = 20.0;

  // --- Dokunma alanı ------------------------------------------------------------
  /// Her düğme ve satır en az bu yükseklikte.
  static const minTouch = 56.0;

  /// İkincil düğmeler ("Ayrıntıyı göster") en az bu yükseklikte.
  static const minTouchSecondary = 48.0;

  // --- Yazı tipi ----------------------------------------------------------------
  /// `assets/fonts/` (OFL, `assets/fonts/OFL.txt`); 400-800 statik dosyalar.
  static const fontFamily = 'PlusJakartaSans';

  /// Uygulamada gerçekten üst üste gelen metin/zemin çiftleri. Kontrast
  /// testi her birini 7:1 eşiğiyle ölçer; yeni bir çift kullanılınca buraya
  /// eklenir.
  static const textPairs = <String, (Color, Color)>{
    'metin / zemin': (textPrimary, background),
    'metin / kart': (textPrimary, card),
    'metin / açık indigo': (textPrimary, primarySoft),
    'ikincil metin / zemin': (textSecondary, background),
    'ikincil metin / kart': (textSecondary, card),
    'ikincil metin / açık indigo': (textSecondary, primarySoft),
    'ana renk yazı / zemin': (primary, background),
    'ana renk yazı / kart': (primary, card),
    'ana renk yazı / açık indigo': (primary, primarySoft),
    'beyaz / ana renk dolgu': (onPrimary, primary),
    'beyaz / gradyan başı': (onHero, heroGradientStart),
    'beyaz / gradyan sonu': (onHero, heroGradientEnd),
    'koyu lacivert / cyan': (onAccent, accent),
    'başarı yazısı / zemin': (successText, background),
    'başarı yazısı / kart': (successText, card),
    'SOS yazısı / kart': (sos, card),
    'SOS yazısı / zemin': (sos, background),
    'SOS yazısı / SOS yüzeyi': (sos, sosSurface),
    'beyaz / SOS dolgu': (onSos, sos),
    'beyaz / SOS koyu zemin': (onSosBackground, sosBackground),
    'açık mor / SOS koyu zemin': (onSosBackgroundMuted, sosBackground),
    'turuncu uyarı / SOS koyu zemin': (sosWarningText, sosBackground),
    'SOS koyu zemin / beyaz düğme': (sosBackground, onSosBackground),
  };

  /// Metin olmayan, anlam taşıyan grafik öğeler (en az 3:1).
  static const graphicPairs = <String, (Color, Color)>{
    'başarı noktası / kart': (successDot, card),
    'nötr nokta / kart': (neutralDot, card),
    'kapalı anahtar izi / kart': (switchTrackOff, card),
    'geri sayım halkası / SOS koyu zemin': (sosRing, sosBackground),
  };
}

/// Tüm butonlar için ortak, büyük dokunma alanı - her ekranda tek tek
/// tekrar etmek yerine burada bir kez tanımlanıp global temaya uygulanıyor.
const _minButtonSize = Size(double.infinity, PatikaTokens.minTouch);
const _buttonTextStyle = TextStyle(
  fontFamily: PatikaTokens.fontFamily,
  fontSize: 17,
  fontWeight: FontWeight.w800,
);
const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(PatikaTokens.radiusButton)),
);

ThemeData buildAppTheme() {
  const text = TextTheme(
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: PatikaTokens.fontFamily,
    scaffoldBackgroundColor: PatikaTokens.background,
    dividerColor: PatikaTokens.divider,
    colorScheme: const ColorScheme.light(
      surface: PatikaTokens.card,
      onSurface: PatikaTokens.textPrimary,
      onSurfaceVariant: PatikaTokens.textSecondary,
      primary: PatikaTokens.primary,
      onPrimary: PatikaTokens.onPrimary,
      primaryContainer: PatikaTokens.primarySoft,
      onPrimaryContainer: PatikaTokens.primary,
      secondary: PatikaTokens.accent,
      onSecondary: PatikaTokens.onAccent,
      error: PatikaTokens.sos,
      onError: PatikaTokens.onSos,
      errorContainer: PatikaTokens.sosSurface,
      onErrorContainer: PatikaTokens.sos,
      outline: PatikaTokens.textSecondary,
      outlineVariant: PatikaTokens.divider,
    ),
    textTheme: text.apply(
      bodyColor: PatikaTokens.textPrimary,
      displayColor: PatikaTokens.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PatikaTokens.background,
      foregroundColor: PatikaTokens.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: PatikaTokens.fontFamily,
        color: PatikaTokens.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: const CardThemeData(
      color: PatikaTokens.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(PatikaTokens.radiusCard)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: _minButtonSize,
        textStyle: _buttonTextStyle,
        backgroundColor: PatikaTokens.accent,
        foregroundColor: PatikaTokens.onAccent,
        elevation: 0,
        shape: _buttonShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: _minButtonSize,
        textStyle: _buttonTextStyle,
        backgroundColor: PatikaTokens.primary,
        foregroundColor: PatikaTokens.onPrimary,
        shape: _buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _minButtonSize,
        textStyle: _buttonTextStyle,
        foregroundColor: PatikaTokens.primary,
        backgroundColor: PatikaTokens.card,
        side: const BorderSide(color: PatikaTokens.primary, width: 2),
        shape: _buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, PatikaTokens.minTouchSecondary),
        foregroundColor: PatikaTokens.primary,
        textStyle: const TextStyle(
          fontFamily: PatikaTokens.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(PatikaTokens.card),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? PatikaTokens.primary : PatikaTokens.switchTrackOff,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? PatikaTokens.primary : PatikaTokens.textSecondary,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: PatikaTokens.primary,
      thumbColor: PatikaTokens.primary,
      inactiveTrackColor: PatikaTokens.primarySoft,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PatikaTokens.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 84,
      indicatorColor: PatikaTokens.primarySoft,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: PatikaTokens.fontFamily,
          fontSize: 13,
          color: states.contains(WidgetState.selected) ? PatikaTokens.primary : PatikaTokens.textSecondary,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? PatikaTokens.primary : PatikaTokens.textSecondary,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: PatikaTokens.card,
      labelStyle: TextStyle(color: PatikaTokens.textSecondary),
      hintStyle: TextStyle(color: PatikaTokens.textSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: PatikaTokens.textSecondary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: PatikaTokens.primary, width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: PatikaTokens.textPrimary,
      iconColor: PatikaTokens.primary,
      subtitleTextStyle: TextStyle(
        fontFamily: PatikaTokens.fontFamily,
        color: PatikaTokens.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
