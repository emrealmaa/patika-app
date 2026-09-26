# Patika companion app - Claude notları

Akıllı gözlük için Flutter yardımcı uygulaması (önce Android). Birincil
kullanıcılar görme engelli: **her şey ekrana bakmadan çalışmalı.**
Mimari: [docs/architecture.md](docs/architecture.md), gözlük protokolü:
[docs/ble_protocol.md](docs/ble_protocol.md).

## Çalışma kuralları (kullanıcıyla kararlaştırıldı)

- Her dosya değişikliğini tek tek göster; kullanıcı onaylar.
- Commit ve push **yalnızca kullanıcı söyleyince**. `TODO.md` commit'lere
  dahil edilmez.
- Her faz sonunda: `flutter analyze` temiz + `flutter test` geçer + özet +
  onay. Mümkünse gerçek telefonda dene.
- Simülasyon önce: her gözlük özelliği `PatikaBleService` +
  `SimulatedBleService`'e eklenir, Test Modu'ndan tetiklenebilir.
- Akış: sınıflandırıcı → `CommandRouter` handler'ı → `FeedbackHub`
  (her sonuç ses + titreşim).
- Her widget'ta Semantics, en az 56 dp, bilgi asla yalnızca renkle.
- Tüm Türkçe metinler `lib/l10n/strings_tr.dart`'ta. Kodda gizli anahtar
  yok (dart-define, örnek: `dart_defines.example.json`).
- Saf mantığa birim testi. Yeni Android izni: ilk gerektiği anda, sesli
  açıklamayla (`PermissionExplainer`).

## Ortam

- Derleme: `flutter run --flavor play` ya da `--flavor direct` (flavor
  zorunlu). APK: `build/app/outputs/flutter-apk/app-<tür>-debug.apk`.
- Test telefonu: Galaxy S24 FE (Android 16), adb seri `R5CY6018HZL`.
- Emülatör `patika_api34` bilgisayarı zorluyor: **gerekirse önce kullanıcıya
  sor**, kendiliğinden başlatma. sdkmanager/avdmanager için
  `JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"`.
- Gizlilik: telefondan alınan, kişi adı içeren loglar iş bitince silinir.

## Nerede kaldık (2026-09-26)

**Bitenler** (hepsi commit'li ve push'lu, son commit `d49a90b`, 227 test):

| Faz | İçerik |
|---|---|
| 1a | Duyuru kuyruğu (öncelikli TTS), titreşim dili, earcon'lar, ayarlar |
| 1b | Arka plan servisi, bağlantı denetçisi (heartbeat, yeniden bağlanma), gözlük protokolü; Dart motorunun etkinlikten ayrılması |
| 2a | Tek dinleme kapısı (VoiceController), evrensel komutlar (dur, tekrar et, komutlar, eğitim, SOS), sesli eğitim |
| 2b | Hızlı Ayarlar karosu; TalkBack'te tetiklenemeyen buton düzeltmesi; ağırlıklı anahtar kelime sınıflandırıcı |
| 3a | Türkçe kişi eşleştirme (kök adayları + Jaro-Winkler), takma adlar, numara okuma |
| 3b | Diyalog yönetimi: ARA/MESAJ çok adımlı (kişi sor, "hangisi?", onay, mesaj dikte + geri okuma) |
| 4a | `play`/`direct` derleme türleri, doğrudan arama (`TelecomManager.placeCall`) ve SMS, "gönderdiğim son mesajı oku" |

**Açık kalanlar:**
- `direct` türü gerçek telefonda **henüz denenmedi**. 4b'nin telefon
  oturumunda birlikte denenecek (gerçek arama/SMS, kullanıcının kendi ikinci
  numarasıyla).
- Ertelenenler: kulaklıkla deneysel sesli araya girme (barge-in); TalkBack'in
  gerçek cihazda baştan sona kontrolü. Dikte sırasında "SOS"un katılığı
  sorusu yanıtsız; şimdilik cümlenin her yerinde tanınıyor.

## Sıradaki: Faz 4b - bildirimler ve gelen arama

**Alınmış kararlar (tekrar tartışma):**
1. Arayanın kimliği **NotificationListenerService** ile alınır,
   CallScreeningService değil.
2. Gözlükte **uzun basma yalnızca telefon çalarken aramayı reddeder**;
   diğer her durumda SOS. SOS sesle her zaman erişilebilir. Dokunma = aramayı aç.
3. Mesaj içeriği **varsayılan olarak yüksek sesle okunur**, ayarlardan
   kapatılabilir. Bu özellik ilk kullanıldığında ya da ilk açılış
   eğitiminde **bir kerelik sesli uyarı**: "Mesaj içerikleri yüksek sesle
   okunuyor, kalabalık ortamda dikkat edin, ayarlardan kapatabilirsiniz."
4. "Bildirimleri sustur" **yalnızca uygulamanın kendi duyurularını**
   susturur; gelen aramalar yine duyurulur.
5. Uygulama seçimi: varsayılan SMS uygulamaları + WhatsApp; ayarlardan
   değiştirilebilir.

**Plan:**
- `PatikaNotificationListener.kt` + Dart kanalı; bildirim erişimi izni
  sesli açıklamayla (sistem ayar ekranına yönlendirme).
- Gelen arama: "Ayşe arıyor" (`high` öncelik); `READ_PHONE_STATE`,
  `ANSWER_PHONE_CALLS` (aç/reddet). Simülasyon ve Test Modu karşılıkları.
- Komutlar: "mesajlarımı oku", "son bildirimleri oku" (son 20 bildirim,
  yalnızca bellekte), "bildirimleri sustur / aç".
- Türkçe ayrılma hali eki: "Ayşe'den" (`lib/l10n/turkish_suffix.dart`).
- Kapanış: 4a + 4b birlikte gerçek telefon testi, sonra commit/push onayı.

Sonrası: Faz 5–8 ilk şartnameye göre.
