import 'package:flutter/foundation.dart';

/// Düşme algılamanın modu (Faz 7c).
///
/// 7c-1'de YALNIZCA `off` ve `shadow` var. SOS tetikleyen açık mod (`on`)
/// 7c-2'de, iki adımlı açma ve acil kişi koşuluyla birlikte eklenecek
/// (CLAUDE.md "Faz 7c kararları" madde 3 ve 6). Bu enum'da `on` olmadığı
/// sürece düşme algılamanın SOS'a giden bir yolu yok.
enum FallMode {
  /// Sensör kapalı, hiçbir şey kaydedilmez.
  off,

  /// Gölge: sensör açık, darbe adımına ulaşan değerlendirmeler yalnızca yerel
  /// kayda yazılır. Hiçbir mesaj gönderilmez, SOS başlamaz.
  shadow,
}

/// Kullanıcı hiç seçmediyse: debug derlemesinde gölge, kullanıcı (release)
/// derlemesinde kapalı (Faz 7c kararı 1).
FallMode defaultFallMode({required bool isDebug}) => isDebug ? FallMode.shadow : FallMode.off;

/// Kayıtlı seçim ([chosen], null = hiç seçilmedi) ya da derleme türü varsayılanı.
FallMode effectiveFallMode(FallMode? chosen, {bool isDebug = kDebugMode}) =>
    chosen ?? defaultFallMode(isDebug: isDebug);
