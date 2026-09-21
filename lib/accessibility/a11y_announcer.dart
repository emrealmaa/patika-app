import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Önemli bir durum değişikliğini (bağlandı/koptu, komut sonucu vb.) hem
/// TalkBack/VoiceOver'a sesli duyuru olarak hem hafif bir titreşimle
/// bildirir. `AppState` gibi widget olmayan yerlerden de çağrılabilsin diye
/// `BuildContext` gerektirmiyor - hem `SemanticsService.announce` hem
/// `HapticFeedback` bağımsız statik API'ler.
///
/// Kasıtlı olarak SADECE kalıcı/anlamlı durum değişimlerinde çağrılmalı
/// (ör. bağlandı/koptu, komut sonucu) - "taranıyor"/"bağlanıyor" gibi geçici
/// ara durumlar burada duyurulmuyor, gereksiz sesli gürültü olmasın diye
/// (bkz. patika/MIMARI.md İlke 2 - bilişsel yük).
void announce(String message) {
  // SemanticsService.announce deprecated (Flutter 3.35+) lehine
  // sendAnnouncement - ama o bir FlutterView/BuildContext istiyor.
  // AppState bir widget değil (BuildContext'i yok) ve komutlar BLE
  // stream'inden asenkron geliyor - context taşımak mimariyi
  // karmaşıklaştırırdı. Bu uygulama tek pencereli (mobil) olduğu için
  // deprecated API hâlâ doğru çalışıyor - çoklu pencere desteği
  // gerekirse (örn. masaüstü) UI katmanına (View.of(context) ile)
  // taşınmalı.
  // ignore: deprecated_member_use
  SemanticsService.announce(message, TextDirection.ltr);
  HapticFeedback.lightImpact();
}
