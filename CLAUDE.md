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
- **Gerçek telefon testleri ertelendi (2026-09-28)** - liste aşağıda,
  "Bekleyen telefon testleri". `direct` türü ve
  `PatikaNotificationListener.kt` gerçek cihazda **henüz hiç denenmedi**.
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

## Bekleyen telefon testleri

Faz 6 süresince yalnızca kod + otomatik test (`flutter analyze` +
`flutter test`) seviyesinde ilerleniyor; gerçek cihaz testleri burada
birikiyor. Yeni yazılan her cihaza bağlı özellik buraya madde olarak eklenir.

- [ ] **Faz 6 - ANA SENARYO (ilk sırada): ekran kapalı/kilitliyken sesle
  navigasyon başlatma.** Kulaklık/gözlükten "X'e götür" denince navigasyonun
  başlaması ve konum duyurularının sürmesi. Doğrulanacaklar:
  (a) eğitimde verilen konum izninden sonra arka plan servisi konum türüyle
  yeniden başlıyor (`BackgroundService.ensureLocationType`);
  (b) ekran kilitliyken ve uygulama arka plandayken konum akışı sürüyor,
  **`ACCESS_BACKGROUND_LOCATION` olmadan** (varsayım: servis uygulama
  görünürken konum türüyle başladığı için "while-in-use" erişimi sürer -
  Android belgelerine dayanıyor, cihazda doğrulanmadı; tutmazsa izin
  gerekliliğini gerekçesiyle kullanıcıya soracağız);
  (c) Galaxy S24 FE / Android 16'da pil optimizasyonu servisi öldürüyor mu;
  (d) izin verilmemişse ya da uygulama ön planda değilken Haritalar yedeğine
  düşülüyor ve nedeni söyleniyor.
- [ ] **Faz 6:** Konum izni akışı (melez): eğitimde sesli açıklamayla istenir;
  reddeden/atlayan için ilk navigasyonda açıklama; ön planda değilse yedek.
  TalkBack açıkken izin penceresi.
- [ ] **Faz 6:** Gerçek GPS ile yürüyüş: `GuidanceConfig` eşikleri (50/15 m
  duyuru, rota dışı 20 m + doğruluk ve 3 okuma, konum belirsiz 40 m / 15 sn,
  varış 20 m) gerçek gürültüyle ayarlanacak. Şehir içi (yüksek bina) ve açık
  alan.
- [ ] **Faz 6:** `geolocator` `forceLocationManager` yedeği (Google Play
  Hizmetleri olmayan telefon, özellikle `direct` türü) ve konum servisi
  kapalıyken davranış.
- [ ] **Faz 6:** Karşıya geçiş duraklaması, dört çıkış kanalı: konum geçişin
  ötesine ilerleyince kendiliğinden, gözlük **çift** dokunuşu, "geçtim"
  komutu ve zaman aşımı. Duraklamadayken rota dışı denetiminin susması.
- [ ] **Faz 6:** **90 sn zaman aşımı kırmızı ışıkta beklemek için kısa
  olabilir** (`GuidanceConfig.crossingMaxPause`): süre dolunca navigasyon
  kullanıcı hâlâ kavşaktayken konuşmaya başlar. Gerçek kavşaklarda (uzun
  ışık döngüleri) ayarlanacak; uzatmak, hatırlatma cümlesine çevirmek ya da
  ışık süresine göre değişken yapmak seçenekler.
- [ ] **Faz 6:** Yön teyidinin gerçek yürüyüşte doğruluğu (konum geçmişinden
  hesaplanan hareket yönü; 15 m ya da doğruluğun 2 katı yürünmüş, doğruluk
  < 10 m, ~0,7 m/s hız eşiği, ilk 100 m); yanlış "rotanın tersi"/"yan"
  oranı; sessizlik + başlangıçtaki "yön bilgisi yürümeye başlayınca gelecek"
  cümlesinin yeterince anlaşılır olup olmadığı. Kapatma: `GuidanceConfig`'de
  `directionCheck: false` (tek satır).
- [ ] **Faz 6:** Karşıya geçiş duraklamasında gözlük tek dokunuşu **dinler**
  (SOS ve sesli komutlar kavşakta erişilebilir kalır; "yardım" SOS yoluna
  gider, testle kilitli), **çift dokunuş** navigasyonu devam ettirir ve o
  sırada "son duyuruyu tekrarla" anlamını geçici olarak yitirir
  (`AppState._onButton`). Kullanıcıyı şaşırtıyor mu? Kavşakta yanlışlıkla
  çift dokunuş (ör. çantaya çarpma) navigasyonu erken devam ettiriyor mu?
- [ ] **Faz 6:** Uygulamanın "ön planda mı" tespiti (`AppLifecycleState.resumed`):
  Hızlı Ayarlar karosu, gözlük ve kilitli ekrandan başlatmada doğru cevap
  veriyor mu (izin yokken yedek akış bunun üstüne kurulu).
- [ ] **Faz 6:** Yalnızca "yaklaşık konum" izni verilirse (Android 12+)
  doğruluk ~km olur: navigasyon "konum belirsiz" der. Kullanıcıya nasıl
  anlatılacağı.
- [ ] **4a:** `direct` türü gerçek arama ve SMS (kullanıcının ikinci
  numarasıyla); izin reddinde `play` davranışına düşme.
- [ ] **4b:** Gerçek gelen arama tespiti - **henüz yazılmadı**, yalnızca
  simülasyon var (`READ_PHONE_STATE`, `ANSWER_PHONE_CALLS`, arayan kimliği
  NotificationListenerService'ten). Yazılınca cihazda denenmeli.
- [ ] **4b:** Bildirim dinleyici gerçek WhatsApp/SMS mesajlarıyla; bir
  kerelik gizlilik uyarısı; "mesajlarımı oku", "son bildirimleri oku",
  "bildirimleri sustur/aç".
- [ ] **4b:** Uygulama seçimi ayarı **yapılmadı** (SMS + WhatsApp sabit) -
  yazılınca cihazda denenmeli.
- [ ] **Faz 2:** Kulaklıkla sesle araya girme (barge-in, ertelendi);
  TalkBack ile uçtan uca kontrol.
- [ ] **Faz 6 (kullanıcı testi):** Navigasyon cümle tarzının ("rota sağa
  sapıyor", "30 metre sonra") gerçek görme engelli kullanıcılarla
  denenmesi (Altınokta Körler Derneği / Mustafa Özhan Kalaç). Emir kipi
  yerine bilgi kipinin yeterince anlaşılır olduğu **henüz bir varsayım**.

## Sıradaki

1. Faz 6c (Sesli Navigasyon: Google istemcisi + akış). 6a ve 6b kodlandı,
   onay bekliyor. Faz 5 iptal edildi (aşağıda).
2. "Bekleyen telefon testleri" (yukarıda) - tarih henüz yok.

## Faz 6 kararları (geçerli, tekrar tartışma)

Alt fazlar: **6a** saf mantık (`lib/navigation/`, kodlandı) → **6b** konum
servisi, `NavigationSession`, geçiş duraklaması, Test Modu, izin/servis türü,
yeni niyetler ("navigasyonu bitir", "ne kadar kaldı", "geçtim"), yön teyidi
(kodlandı, onay bekliyor; commit yok) → **6c** Google Routes/Places
istemcisi, `--dart-define` anahtarı, `NavigationFlow` (NAVİGASYON'daki
"Şunu anladım" teyidinin yerini alır), yedek akış (`NavigationStart`
sonuçlarına göre Haritalar), `NavigationHandler`'ın oturuma bağlanması,
belgeler (`architecture.md`, README).

6b'de navigasyonu başlatan tek yol Test Modu'ndaki simülasyondur; sesli
"X'e götür" hâlâ eski Google Haritalar akışını açar (6c'de değişecek).

1. **Bilgi kipi, emir yok** ("30 metre sonra rota sağa sapıyor"). İstisna
   yok. Yasaklı kelimeler `patika/MIMARI.md`'den; navigasyona ek olarak
   "güvenli" ve "açık". `test/navigation_language_test.dart` `Tr`'nin
   "Navigasyon (Faz 6)" bölümünü ve üretilen tüm cümleleri tarar. Google'ın
   kendi talimat metni asla seslendirilmez.
2. **Karşıya geçiş kararı navigasyonun değil**, Kavşak Geçiş Asistanının.
   Geçiş noktasında navigasyon susar (duraklar), rota dışı denetimi de
   durur. Çıkış dört kanaldan: konum geçişin 25 m ötesine ilerleyince,
   gözlük çift dokunuşu, "geçtim", zaman aşımı (varsayılan 90 sn,
   `GuidanceConfig.crossingMaxPause`). Tek dokunuş duraklamada da DİNLER:
   SOS ve sesli komutlar kavşakta erişilebilir kalmalı.
3. **Konum izni: melez.** Eğitimde sesli açıklamayla istenir; servis, izin
   varsa ve uygulama görünürken konum türüyle başlar/yeniden başlar (arka
   planda konum türü başlatılamaz). Reddeden/atlayan için ilk navigasyonda
   açıklama; uygulama ön planda değilse Haritalar yedeği.
   `ACCESS_BACKGROUND_LOCATION` istenmez (doğrulama: ilk telefon testi).
4. **Yön teyidi** hareket yönünden hesaplanır (eklentinin `heading`'i
   değil), ~0,7 m/s altında verilmez, navigasyon başında bir kez "yön
   bilgisi yürümeye başlayınca gelecek" denir. Yasaklı kelime testine tabi.
5. Paketler: `geolocator` (MIT), `http` (BSD-3) - ikisi de ticari kullanıma
   uygun; `geolocator_android` Google Play Hizmetleri'ne dayanır
   (`forceLocationManager` yedeği bu yüzden).

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
