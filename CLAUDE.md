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

## Nerede kaldık (2026-09-28)

**Bitenler** (hepsi commit'li ve push'lu, son kod commit'i `d8d4ac8`, 260 test):

| Faz | İçerik |
|---|---|
| 1a | Duyuru kuyruğu (öncelikli TTS), titreşim dili, earcon'lar, ayarlar |
| 1b | Arka plan servisi, bağlantı denetçisi (heartbeat, yeniden bağlanma), gözlük protokolü; Dart motorunun etkinlikten ayrılması |
| 2a | Tek dinleme kapısı (VoiceController), evrensel komutlar (dur, tekrar et, komutlar, eğitim, SOS), sesli eğitim |
| 2b | Hızlı Ayarlar karosu; TalkBack'te tetiklenemeyen buton düzeltmesi; ağırlıklı anahtar kelime sınıflandırıcı |
| 3a | Türkçe kişi eşleştirme (kök adayları + Jaro-Winkler), takma adlar, numara okuma |
| 3b | Diyalog yönetimi: ARA/MESAJ çok adımlı (kişi sor, "hangisi?", onay, mesaj dikte + geri okuma) |
| 4a | `play`/`direct` derleme türleri, doğrudan arama (`TelecomManager.placeCall`) ve SMS, "gönderdiğim son mesajı oku" |
| 4b | Gelen arama simülasyonu (`PatikaCallService`/`SimulatedCallService`); bildirim erişimi izni + `PatikaNotificationListener.kt` (varsayılan SMS + WhatsApp mesajları); gelen mesaj duyurusu + bir kerelik gizlilik uyarısı (`LoudMessagesNotice`); ayrılma hali eki ("Ayşe'den"); "mesajlarımı oku", "son bildirimleri oku" (`IncomingMessageLog`, bellekte son 20), "bildirimleri sustur/aç" (`Settings.notificationsMuted`) |

**Açık kalanlar:**
- **Gerçek telefon testi: 2026-09-29.** 4a + 4b birlikte, `direct` türü dahil
  (gerçek arama/SMS, kullanıcının kendi ikinci numarasıyla; gerçek WhatsApp/
  SMS bildirimi). `direct` türü ve `PatikaNotificationListener.kt` gerçek
  cihazda **henüz hiç denenmedi**.
- Gerçek gelen arama durumu **yazılmadı**: `PatikaCallService` hâlâ yalnızca
  simülasyon. Gereken: `READ_PHONE_STATE`, `ANSWER_PHONE_CALLS` (aç/reddet)
  ve arayan kimliği (karar 1: NotificationListenerService'ten).
- Ertelenenler: kulaklıkla deneysel sesli araya girme (barge-in); TalkBack'in
  gerçek cihazda baştan sona kontrolü.
- **Karara bağlandı:** Dikte sırasında (mesaj gövdesi yazdırılırken) SOS
  artık DUR/TEKRAR gibi yalnızca TÜM cümle "yardım"/"imdat"/"acil durum"
  ise tetikleniyor (nezaket sözcükleriyle birlikte, ör. "lütfen imdat" de
  sayılır) - aksi halde dikte edilen mesaj içeriğinde bu kelimeler geçince
  mesaj kaybolurdu. Dikte dışı diyalog cevaplarında (isim, onay) güvenlik-
  önce davranış aynen korunuyor: cümlenin her yerinde eşleşir.
  (`classifyControl(..., dictation: ...)`, `voice_intent_classifier.dart`)

## Sıradaki

1. 2026-09-29: 4a + 4b gerçek telefon testi (yukarıda).
2. Faz 6 (ilk şartnameye göre). Faz 5 iptal edildi (aşağıda).

## Faz 4b kararları (geçerli, tekrar tartışma)

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
5. Uygulama seçimi: varsayılan SMS uygulamaları + WhatsApp. (Şu an sabit;
   ayarlardan değiştirme henüz yok.)
6. "Mesajlarımı oku" okunmamışları içerikle okur ve okunmuş sayar; "son
   bildirimleri oku" yalnızca göndereni özetler, okunmuşluğu etkilemez.
   Susturma kaydı değil yalnızca duyuruyu engeller.

## Faz planı

Faz 6–8 ilk şartnameye göre.

**Faz 5 (Görsel Yardım - OCR, nesne tespiti, sahne anlatımı) İPTAL EDİLDİ
(2026-09-28).** Gerekçe:
1. Bu, Python tarafında zaten var ve çalışıyor (`ocr.py`, `ozel_tespit.py`,
   `detector.py`) - Flutter'da ML Kit ile sıfırdan yeniden yazmak aynı işi
   iki kez yapmak olurdu.
2. Nihai mimaride görsel analiz zaten gözlük+telefon sisteminin (Python/
   ileride Dart'a taşınacak Katman 1 - bkz. `patika/CLAUDE.md`) sorumluluğu;
   companion app'e ayrı bir "kendi başına görsel asistan" özelliği eklemek
   projenin asıl misyonuyla (kullanıcıyı güvenli bir şekilde bir noktadan
   diğerine götürmek) örtüşmüyor, mimariyi gereksiz yere bölüyor.
3. Kalıcı bir "asla yapılmayacak" kararı değil - donanım gelip Python→Dart
   taşıması (`patika/CLAUDE.md` Z7) netleştiğinde ayrı ve bilinçli bir karar
   olarak yeniden gündeme gelebilir.

Faz numaraları **kaydırılmadı** (6, 7, 8 aynı kalıyor, "Faz 5" boş) - diğer
belgelerdeki "Faz 7 = SOS" gibi referanslar bozulmasın diye. OKU niyeti
(`ocr_handler.dart`) yer tutucu olarak kalıyor. `frm` (WiFi kare) komutu
ayrılmış kalıyor; görsel yardım için değil, Katman 1 görüntü kanalı için
(Z7 taşımasıyla netleşecek).
