import 'package:flutter/foundation.dart';

/// Düşme algılamanın modu (Faz 7c).
///
/// `on` (açık mod, 7c-2) bu enum'a eklendi ama **tek başına hiçbir şey
/// tetiklemez**: monitör `on`'da gölgedeki gibi kayıt yazar ve aday akışı
/// yayınlar; bu akışı dinleyip geri sayım başlatan köprü ayrı bir sınıftır
/// (`lib/sos/` altında, sonraki adım). `on` yalnızca iki adımlı açma
/// (`FallEnableSession`) ve kapılardan ([FallOpenModeGate]) geçince seçilir.
enum FallMode {
  /// Sensör kapalı, hiçbir şey kaydedilmez.
  off,

  /// Gölge: sensör açık, darbe adımına ulaşan değerlendirmeler yalnızca yerel
  /// kayda yazılır. Hiçbir mesaj gönderilmez, acil durum akışı başlamaz.
  shadow,

  /// Açık (deneysel, opt-in): gölgedeki gibi kayıt + aday akışı. Adaylar
  /// köprüye gider; köprü geri sayımı başlatır.
  on;

  /// Sensör çalışmalı mı? (`shadow` ve `on`.)
  bool get runsSensor => this != off;
}

/// Kullanıcı hiç seçmediyse: debug derlemesinde gölge, kullanıcı (release)
/// derlemesinde kapalı (Faz 7c kararı 1). Varsayılan hiçbir zaman `on` değil.
FallMode defaultFallMode({required bool isDebug}) => isDebug ? FallMode.shadow : FallMode.off;

/// Kayıtlı seçim ([chosen], null = hiç seçilmedi) ya da derleme türü varsayılanı.
FallMode effectiveFallMode(FallMode? chosen, {bool isDebug = kDebugMode}) =>
    chosen ?? defaultFallMode(isDebug: isDebug);
