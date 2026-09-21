import 'package:flutter/material.dart';

/// WCAG AAA hedefleyen, erişilebilirlik-öncelikli renk paleti.
///
/// `ColorScheme.fromSeed` KASITLI OLARAK kullanılmıyor - estetik uyum için
/// optimize eder, kontrast oranı garanti etmez. Burada renkler elle
/// seçildi: siyah zemin (#000000) + beyaz metin (#FFFFFF) = 21:1 kontrast
/// oranı, AAA'nın istediği 7:1'in çok üzerinde. Durum renkleri (success/
/// warning/info) SADECE yardımcı/dekoratif görsel işaret olarak kullanılır
/// - hiçbir durum bu renklere bağlı kalınarak anlatılmaz, her zaman beyaz
/// metinle de ifade edilir (bkz. ekranlardaki kullanım).
class AppColors {
  AppColors._();

  static const background = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const onSurface = Color(0xFFFFFFFF);
  static const onSurfaceMuted = Color(0xFFE0E0E0);

  /// Sadece dekoratif/yardımcı işaret - asla tek başına anlam taşımaz.
  static const success = Color(0xFF00E676);
  static const warning = Color(0xFFFFD600);
  static const info = Color(0xFF40C4FF);
  static const neutral = Color(0xFFBDBDBD);
}

/// Tüm butonlar için ortak, büyük dokunma alanı - her ekranda tek tek
/// tekrar etmek yerine burada bir kez tanımlanıp global temaya uygulanıyor.
const _minButtonSize = Size(double.infinity, 56);
const _buttonTextStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      primary: AppColors.info,
      onPrimary: Colors.black,
      secondary: AppColors.info,
      onSecondary: Colors.black,
      error: Color(0xFFFF5252),
      onError: Colors.black,
    ),
    textTheme: const TextTheme().apply(
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.onSurface,
      titleTextStyle: TextStyle(
        color: AppColors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Color(0xFF333333)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: _minButtonSize,
        textStyle: _buttonTextStyle,
        backgroundColor: AppColors.info,
        foregroundColor: Colors.black,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _minButtonSize,
        textStyle: _buttonTextStyle,
        foregroundColor: AppColors.onSurface,
        side: const BorderSide(color: AppColors.onSurface, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.info
            : AppColors.neutral,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.info.withValues(alpha: 0.5)
            : const Color(0xFF424242),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.info,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
      ),
      iconTheme: WidgetStateProperty.all(
        const IconThemeData(color: AppColors.onSurface),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: AppColors.onSurface),
      hintStyle: TextStyle(color: AppColors.onSurfaceMuted),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.onSurface),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.info, width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: AppColors.onSurface,
      iconColor: AppColors.onSurface,
    ),
  );
}
