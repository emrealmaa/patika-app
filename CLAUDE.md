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

## Nerede kaldık (2026-10-05)

**Bitenler** (7b-1 `c4dcafe`, 7b-2 `849bcce`, arayüz sadeleştirmesi
`05b77ea`/`6c436cd`/`d08619a`; 628 test). **Faz 7c ve Faz 8
İPTAL EDİLDİ (2026-10-01)**, bkz. "Faz planı". Aşağıdaki tabloda yoklar;
7c-1 (`a4c49b5`) ve 7c-2 (`c632967`, `124b93b`) commit'leri git geçmişinde:

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
| 6 | Navigasyon: saf mantık (6a), konum servisi + `NavigationSession` + karşıya geçiş duraklaması (6b), Google Routes/Places + `NavigationFlow` (6c) |
| 7a | SOS çekirdeği: durum makinesi + geri sayım + gönderim (7a-1), uygulamaya bağlama: gözlük, sesli iptal, ekran, 112 teklifi (7a-2), acil kişi kurulumu: sesle ekle/sil/liste, izin akışı, isteğe bağlı rıza SMS'i (7a-3, `6663ac1`); SOS telefon deneme listesi `docs/sos_phone_test_checklist.md` (`f8a1823`) |
| 7b | Pil uyarıları: telefon (`BatteryProbe.kt`, 30 sn yoklama) + gözlük (`batt`), `BatteryMonitor`, meşgulken erteleme, Test Modu taklidi (7b-1, `c4dcafe`); DURUM niyeti ("durum", "pil ne kadar") + `StatusHandler` (7b-2) |
| Arayüz | Arayüz sadeleştirmesi: release'te gerçek BLE ile açılış (`05b77ea`); gizli Test Modu (Ayarlar'da sürüm satırına 7 dokunuş, `package_info_plus`, her açılışta `low` öncelikli "Test modu açık", simülasyon anahtarı Test Modu'nda) + teknik sızıntı temizliği (cihaz kimliği yok, okunur komut adları) (`6c436cd`); telefon testi maddeleri (`d08619a`) |

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

- [ ] **YÜKSEK ÖNCELİK - gözlük SoftAP'ına bağlıyken telefonun internet
  erişimi.** SoftAP internetsizdir; Android buna bağlanınca mobil veriyi
  bırakabilir. Etkilenenler: Routes/Places (navigasyon), Gemini, hava
  durumu. Uygulamaya özel ağ bağlama (`WifiNetworkSpecifier`) denenecek:
  akış SoftAP'tan, diğer istekler mobil veriden gitmeli. **Samsung One UI'da
  (Galaxy S24 FE) doğrulanacak**; One UI'ın "ağ zayıfsa mobil veriye geç"
  (akıllı ağ değiştirici) davranışı ve internetsiz Wi-Fi uyarısı da
  bakılacak. Henüz kod yok, gözlük Wi-Fi'ı hazır olunca.

- [ ] **Faz 7 (SOS, YÜKSEK ÖNCELİK) - konum, ekran kilitli ve cepteyken:**
  ekran kilitli, telefon cepte, **gözlük uzun basışıyla** tetiklenen SOS'ta
  konum alınıyor mu? Bakılacaklar: arka plan servisi **konum türüyle**
  çalışıyor mu (`BackgroundService.ensureLocationType`), konum izni servis
  BAŞLARKEN verilmiş mi (izin sonradan verilirse servis konum türüyle yeniden
  başlıyor mu), `ACCESS_BACKGROUND_LOCATION` olmadan "kullanım sırasında"
  erişimin ekran kilitliyken sürüp sürmediği (Faz 6 ana senaryosuyla aynı
  varsayım), Galaxy S24 FE / Android 16'da pil optimizasyonu; konum
  gelmezse "konumsuz gönder + tek takip SMS'i" akışı.
- [ ] **Faz 7 (SOS):** arama sırasında konuşmama ve arama sonu tespiti:
  `AudioModeCallMonitor` (`AudioManager.getMode()`, kanal `patika/audiomode`)
  **cihazda hiç doğrulanmadı**. Bakılacaklar: giden aramanın çalma
  aşamasında (karşı taraf açmadan) `MODE_IN_CALL` görülüyor mu (izin
  gerekmeden), yoksa yalnızca bağlanınca mı; `startGrace` (30 sn) bu durumda
  yeterli mi; OEM'e göre fark (Galaxy S24 FE / One UI); modun aramadan
  ÇIKARKEN art arda 2 okumada (`stableReads`) kararlı biçimde değişip
  değişmediği. Doğrulanamazsa (`unknown`) SOS **hiç konuşmaz** ve yalnızca
  geçmişe yazar - bunun gerçek cihazda ne sıklıkla olduğu izlenecek.
  **Ayrıca:** `speech_to_text`'in Bluetooth kulaklık varken açtığı SCO
  kanalının (`BluetoothHeadset.startVoiceRecognition`, bkz.
  `sos_call_monitor.dart` doc'u) gerçekten `AudioManager.getMode()`'u
  `MODE_IN_COMMUNICATION`'a geçirip geçirmediği; geçiriyorsa gerçek bir SOS
  araması sürerken (kullanıcı elle başka bir sesli komut başlatırsa) izin
  algısını nasıl etkilediği (beklenen: yalnızca gecikme/susma, asla erken
  konuşma). **Ek, adreslenmemiş soru:** kendi STT'mizin Bluetooth SCO'yu
  açması, gerçek aramanın ses kanalıyla (aynı SCO) çakışıp arama sesinde
  kesinti yaratır mı - tespit mantığından bağımsız bir donanım sorusu.
- [ ] **Faz 7b (pil):** `BatteryProbe.kt` Galaxy S24 FE'de doğru yüzdeyi ve
  şarj durumunu veriyor mu (sticky `ACTION_BATTERY_CHANGED`); ekran kilitli ve
  uygulama arka plandayken 30 sn'lik yoklama sürüyor mu (Dart zamanlayıcısı,
  pil optimizasyonu); şarja takma/çıkarma ve %100'de "doldu" duyurusu;
  Test Modu taklidinin (kaydırıcı + "şarjda") gerçek cihazda uyarıyı tetiklemesi.
- [ ] **Faz 7b (pil, kullanıcı):** Eşikler (telefon 30/15/5, gözlük 20/10/5)
  gerçek kullanımda erken/geç mi; %5'te 5 dk'lık titreşim hatırlatması
  rahatsız ediyor mu; gözlük eşikleri gerçek pil süresi ölçülünce (TODO madde
  15) yeniden ayarlanacak.
- [ ] **Faz 7 (SOS):** Acil kişi listesinin Android yedeğine girmediği
  (`Context.getNoBackupFilesDir`, kanal `patika/emergency_contacts`):
  `adb backup`/Google hesap yedeği alıp geri yüklendiğinde acil kişilerin
  GELMEDİĞİ, ayarların/takma adların geldiği; cihazdan cihaza aktarımda
  (Android "Switch") aynı davranış.
- [ ] **Faz 7 (SOS) - adım adım deneme listesi:**
  [docs/sos_phone_test_checklist.md](docs/sos_phone_test_checklist.md).
  Aşağıdaki SOS maddeleri bu listenin ayrıntılarıdır.
- [ ] **Faz 7 (SOS) - acil kişi kurulumu:** "acil kişi ekle" ile gerçek
  rehberden ekleme; `direct`de SMS izni penceresinin kurulum sırasında
  açılması (TalkBack'le); rıza SMS'inin **ikinci numaraya** gerçekten
  gitmesi (asla üçüncü bir kişiye/112'ye değil); izin reddedilince "SMS
  izni verilmedi" notunun duyulması; "acil kişi sil" isimsiz sorulduğunda
  birden çok kişi arasından TalkBack'le seçim.
- [ ] **Faz 7 (SOS, YÜKSEK ÖNCELİK) - gerçek cihazda uçtan uca:** SOS'un
  **ikinci numarayla** denenmesi (asla gerçek 112 ile değil). Bakılacaklar:
  (a) kişi aranınca **ses hoparlörden mi** çıkıyor (eller serbest gerekir;
  `direct` aramasında hoparlör kendiliğinden açılmıyor olabilir);
  (b) **çift SIM**: SMS ve arama hangi SIM'den gidiyor, varsayılan SIM
  seçimi; (c) **şebeke yok / uçak modu**: gönderim başarısız raporu ve
  "Gönderilemedi, 112'yi aramak için çift dokunun" cümlesi; (d) gönderim
  sonucu raporu: "gönderildi" yalnızca `sent` iken, çok parçalı SMS'te tüm
  parçalar; (e) konum izni yokken / konum gelmezken konumsuz gönderim ve
  tek takip SMS'i; (f) ekran kilitli ve telefon cepteyken sesli "iptal" ve
  gözlük dokunuşu; geri sayım bipinin mikrofona karışıp karışmadığı;
  (g) SMS izni yokken sessiz kalmayıp nedenini söylemesi.
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
- [ ] **Faz 6 (Google):** Anahtar Android uygulama kısıtlamalıyken (paket +
  SHA-1) istekler geçiyor mu; `X-Android-Package`/`X-Android-Cert` başlıkları
  artık gönderiliyor (bkz. Faz 6 kararları, madde 7) ama cihazda
  doğrulanmadı. debug, release/`direct` ve Play imzası için ayrı SHA-1
  satırları Cloud kısıtına eklenmeli.
- [ ] **Faz 6 (Google):** Gerçek anahtarla Routes ve Places: yanıt biçimi
  belgelerden yazıldı, gerçek yanıtla **hiç sınanmadı**; Türkçe yer
  adlarının (STT çıktısı "Kadıköy iskelesi") Places'te bulunma oranı, "hangisi?"
  sorusu, 5 km yakın-sonuç önceliği; anahtar kısıtlaması (yalnız bu iki API) ve
  kota; yeniden rota isteklerinin (30 sn aralık) maliyeti.
- [ ] **Faz 6 (Google):** Karşıya geçiş tespiti Google'ın Türkçe talimat
  metnindeki kalıplara ("karşıya", "yaya geçidi") dayanıyor - **varsayım**.
  Gerçek rotalarda ne kadarını yakalıyor, yanlış pozitif (gereksiz duraklama)
  var mı, 20 m bölme geçişi doğru yere oturtuyor mu?
- [ ] **Faz 6 (Google):** Sokak adsız duyurular ("30 metre sonra rota sağa
  sapıyor") kullanıcılar için yeterli mi, sokak adı isteniyor mu (isteniyorsa
  Roads/Geocoding gibi ek kaynak gerekir)?
- [ ] **Faz 6 (Google):** Anahtarsız yedek akış: Haritalar açılıyor mu, TalkBack
  ile devam edilebiliyor mu; onay sorusundaki nedenler ("Konum izni yok,
  uygulamayı açıp konum iznini verin") anlaşılır mı.
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
- [ ] **Arayüz sadeleştirmesi - gerçek BLE açılışı:** release/`direct`
  derlemesi ilk açılışta **gerçek BLE** ile başlıyor mu
  (`AppState.defaultSimulated`, sahte gözlük yok); Bağlantı sekmesinde
  simülasyon anahtarı ve cihaz kimliği (MAC/UUID) görünmüyor.
- [ ] **Arayüz sadeleştirmesi - gizli Test Modu:** Ayarlar'daki sürüm
  satırına TalkBack ile 7 dokunuş: sesli sayaç ("N dokunuş daha"), Test
  Modu sekmesi en sonda beliriyor; uygulama yeniden açılınca her açılışta
  "Test modu açık" duyuruluyor; "Test modunu gizle" ile kapanıyor ve
  sonraki açılışta sessiz.
- [ ] **Arayüz sadeleştirmesi - hatırlatma ile Hızlı Ayarlar:** Test Modu
  açıkken uygulama **Hızlı Ayarlar karosundan** açılınca "Test modu açık"
  hatırlatması (öncelik `low`) hemen başlayan dinlemeyle üst üste geliyor
  mu: TTS mikrofona karışıp yanlış komut tanınıyor mu, dinleme hatırlatmayı
  kesiyor mu, hatırlatma 10 sn'den uzun bekleyip atılıyor mu.

## Sıradaki

1. Faz 6 kodlandı (6a, 6b, 6c commit'li). Faz 7: 7a (SOS çekirdeği) ve 7b
   (pil + durum) bitti. **Faz planı 7b ile sona erer:** 7c (düşme algılama),
   Faz 5 ve Faz 8 iptal edildi (aşağıda). Sırada yalnızca "Bekleyen telefon
   testleri".
2. "Bekleyen telefon testleri" (yukarıda) - tarih henüz yok.
3. **Telefon testi hâlâ bekliyor (2026-10-05), ilk oturumda bakılacaklar:**
   release'te gerçek BLE ile açılış (sahte gözlük yok); TalkBack ile sürüm
   satırına 7 dokunuş (gizli Test Modu); SOS'un ikinci numarayla uçtan uca
   denenmesi (asla gerçek 112 ile değil,
   `docs/sos_phone_test_checklist.md`).

## Faz 6 kararları (geçerli, tekrar tartışma)

Alt fazlar: **6a** saf mantık (`lib/navigation/`, kodlandı) → **6b** konum
servisi, `NavigationSession`, geçiş duraklaması, Test Modu, izin/servis türü,
yeni niyetler ("navigasyonu bitir", "ne kadar kaldı", "geçtim"), yön teyidi
(commit'li) → **6c** Google Routes/Places istemcisi (`http`),
`--dart-define` anahtarı, `NavigationFlow` (NAVİGASYON'daki "Şunu anladım"
teyidinin yerini aldı; teyit kodu tamamen kaldırıldı), `NavigationBackend`
(gerçek mod + her adımda Haritalar yedeği), belgeler (commit'li).

Sesli "X'e götür" artık: yer sor/seç → rota özeti + onay → uygulama içi
navigasyon. Anahtar yoksa ya da konum hazır değilse (izin yok, ön planda
değil, servis kapalı, konum alınamadı, arama/rota hatası) aynı sesli akış
Google Haritalar'a düşer ve nedeni söyler.

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
   (`forceLocationManager` yedeği bu yüzden). `geolocator` Linux'ta MPL-2.0
   üç paket çeker (dbus, geoclue, gsettings); Android APK'ya girmiyor.
6. **Sokak adı yok:** Google Routes API adımlarında yapısal sokak adı alanı
   yok (yalnızca manevra + serbest metin `instructions`). Serbest metinden
   sokak adı ayıklamak kırılgan olduğundan duyurular "30 metre sonra rota
   sağa sapıyor" biçiminde, sokak adsız. Talimat metni yalnızca karşıya
   geçiş tespiti (`looksLikeCrossing`, sezgisel) için okunur, seslendirilmez.
   Geçiş adımı 30 m'den uzunsa yalnızca ilk 20 m geçiş sayılır.
7. **Anahtar:** `--dart-define=PATIKA_MAPS_API_KEY` (`MapsConfig`); yoksa
   Google istemcileri hiç kurulmaz. Anahtar yalnızca `X-Goog-Api-Key`
   başlığında gider, hata mesajlarına ve günlüklere girmez. README'de
   kısıtlama/kota ve "ürün aşamasında ara sunucu" notu var.

   **Anahtar kısıtlama kontrol listesi (Google Cloud Console, anahtarı
   koymadan önce):**
   - *Uygulama kısıtlaması:* Android uygulamaları. Paket adı
     `com.patika.patika_app` (`play` ve `direct` aynı) + SHA-1 parmak izi.
     SHA-1 sayısı kadar satır: debug keystore (`keytool -list -v -keystore
     ~/.android/debug.keystore -alias androiddebugkey -storepass android`),
     `direct` için kendi imza anahtarımız, Play dağıtımında ayrıca **Play
     Console → Uygulama bütünlüğü'ndeki uygulama imzalama SHA-1'i**.
   - *API kısıtlaması:* yalnızca **Routes API** ve **Places API (New)**.
     Başka hiçbir API seçili olmasın.
   - *Bütçe uyarısı:* Faturalandırma → Bütçeler ve uyarılar'da aylık bütçe
     + %50/%90/%100 e-posta uyarısı. Uyarı harcamayı **durdurmaz**; asıl
     sınır için API → Kotalar'dan günlük istek üst sınırı da konur.
   - **Karar (onaylandı):** `X-Android-Package` ve `X-Android-Cert` başlıkları
     eklenecek. Google Cloud kısıtına **hem debug hem release SHA-1'i**
     (ve `direct`/Play imzaları) eklenecek; biri eksikse o derlemede
     istekler 403 alır.
   - **Yapıldı (Adım 0):** `google_client.dart` her Routes/Places isteğine
     `X-Android-Package` ve `X-Android-Cert` (SHA-1, iki nokta yok, büyük
     harf) ekler. Değerler çalışan imzadan native kanaldan (`patika/identity`,
     `AppIdentity.kt`) okunur; okunamazsa istek başlıksız gider (kısıtlı
     anahtarla 403 → Haritalar yedeği). Parmak izi günlüğe ve hata
     mesajlarına yazılmaz. Cihazda doğrulanacak (bekleyen telefon testleri).

## Faz 7 kararları (SOS; hassas, tekrar tartışma)

Alt fazlar: **7a** SOS çekirdeği (durum makinesi, geri sayım, acil kişi,
gönderim) · **7b** pil uyarıları + "durum" komutu. (7c düşme algılama
İPTAL EDİLDİ, 2026-10-01; SOS yalnızca elle tetiklenir: sesli "yardım" ve
gözlük uzun basışı.)

1. **Dağıtım:** İlk sürüm `direct` ile dağıtılır. Play istisna başvurusu
   ilk sürümde açılmaz, Play için sonra karar verilir. **`play` türünde
   SOS "desteklenmiyor" (Seçenek 2):** geri sayım başlamaz; uzun basış ve
   "yardım" sessiz kalmaz, hemen "Bu sürümde acil durum mesajı
   gönderilemiyor" der (112'yi aramak ya da telefonun kendi acil durum
   özelliğini kullanmak da söylenir). Ekran açan yedek (Seçenek 1)
   yapılmadı: mesajın gittiğini doğrulayamayız, yanıltıcı olurdu.
2. **Geri sayım:** Elle SOS 7 sn. İptal **varsayılanı
   GÖNDER**: kullanıcı bir şey yapmazsa SOS gider. Geri sayım sesli, kısa
   aralıklı bip. İptal kanalları: sesli iptal, gözlük dokunuşu, telefon
   ekranı. **Sesli iptal listesi:** "iptal", "iptal et", "yanlış alarm",
   "vazgeç", "gerek yok". **"dur" geri sayımı iptal ETMEZ** (ve evrensel
   DUR, SOS'u durdurmaz). Gerekçe: yanlışlıkla iptal olan gerçek bir SOS,
   yanlışlıkla giden bir SOS'tan çok daha kötüdür; "dur" başka bağlamda
   söylenmiş ya da TTS'i kesmek için söylenmiş olabilir.
3. **112:** Ayrı ayar, varsayılan kapalı. Test numarası yalnızca debug'da ve
   enjekte edilebilir. Release'te 112 sabiti değiştirilemez; testlerde gerçek
   112 hiçbir yolla aranamaz. Asılsız 112 ihbarı için idari para cezası var
   (5326 md. 42/A; kanun metninde 15.000 TL, yıllık yeniden değerleme;
   yayın öncesi mevzuat.gov.tr ve avukatla doğrulanacak). Ayar açılırken bu
   sesle söylenir.
4. **Konum:** Alma, geri sayım BAŞLARKEN başlar. Geri sayım bitince konum
   varsa kullanılır; yoksa en fazla 2-3 sn beklenir; yine yoksa konumsuz
   gönderilir ve konum gelirse **tek** takip SMS'i atılır. Konum izni yoksa
   konumsuz gönderilir ve bu sesle söylenir.
5. **Gönderim sırası:** SMS acil kişilerin **hepsine**; SMS sonuçları
   söylenir; ardından **tek arama**: 112 ayarı açıksa 112, kapalıysa ilk
   kişi. Elle SOS'ta hiçbir SMS gitmediyse, SMS sonuçlarından sonra kısa
   bir pencerede (6 sn, `offerDecisionWindow`)
   onaylı teklif sunulur: "112'yi aramak için çift dokunun". Bu pencerede
   çift dokunuş 112 onayıdır, "tekrar et" değil; onaylanırsa kişi aranmaz.
   Ön kontrolde takılan SOS'ta (kişi yok, izin yok) aynı teklif 20 sn açık
   kalır (her kaynakta).
   **Arama sırasında konuşma yok:** SMS sonuçları arama BAŞLAMADAN, konuşma
   bitince söylenir; arama başladıktan sonra TTS araya girmez; geç kalan
   (10 sn'de bitmeyen) ve sonradan başarısız olan SMS sonuçları ile takip
   SMS'i duyurusu arama BİTTİKTEN sonra özetlenir. Arama sonu tespiti
   (`AudioModeCallMonitor`, kanal `patika/audiomode`) `AudioManager.getMode()`
   ile izin istemeden yapılır: `MODE_IN_CALL`/`MODE_IN_COMMUNICATION` sürüyor
   sayılır, arama modundan art arda 2 okumada çıkış "bitti" sayılır. **Bitiş
   doğrulanamazsa** (30 sn içinde arama modu hiç görülmezse, mod okunamazsa,
   ya da 3 saatlik üst süre aşılırsa) sonuç **hiç konuşulmaz** - yalnızca
   SOS geçmişine yazılır; amaç 112 (ya da acil kişi) görüşmesinin üstüne
   uygulamanın asla konuşmamasıdır. **Cihazda hiç doğrulanmadı** (bkz.
   "Bekleyen telefon testleri").
6. **Sonucu doğru söyle:** "SOS gönderildi" yalnızca gönderim sonucu
   başarılıysa (`SmsSendStatus.sent`: mesaj operatöre ulaştı) söylenir.
   "İletildi/ulaştı" denmez: teslim raporu yok, karıştırılmaz. Başarısızsa
   "Gönderilemedi, 112'yi aramak için çift dokunun"; çift dokunuş onayıyla
   112 aranır. İzin eksikse SOS sessiz kalmaz, nedenini söyler.
7. **Acil kişi kurulumu:** SMS izni (yalnızca `direct`) acil kişi kurulumunda
   sesli açıklamayla istenir. Kişi yoksa "Acil kişi kurulu değil" ile
   bitmez: 112 ayarı kapalıysa "Acil kişi yok. 112'yi aramak için çift
   dokunun" denir, çift dokunuş onayıyla 112 aranır. Rıza SMS'i isteğe bağlı
   ve yalnızca `direct`. Canlı konum paylaşımı kapsam dışı.
8. **Eğitim metni:** "Patika acil durum servisi değildir." cümlesi eğitime
   girer (SOS anlatılırken). **Bilinen tutarsızlık (TODO.md madde 17):** bu
   cümle "acil kişilerinize mesaj gönderilir" diyor, ama bu yalnızca
   `direct` derlemesinde doğru; `play`'de SOS "gönderilemiyor" der. `play`
   dağıtımı gündeme gelirse eğitim metni derleme türüne göre ayrılmalı.
9. **Düşme algılama (7c): İPTAL EDİLDİ (2026-10-01)**, bkz. "Faz planı".
   SOS'u yalnızca kullanıcı tetikler; otomatik tetikleyici yok.
10. **Uzun basış:** Doğrudan geri sayım başlatır; firmware'de 3 sn eşiği
   (TODO.md madde 16, "firmware ile netleşecek"). 60 sn'de en fazla bir
   SOS sınırı **iptal edilen ya da gönderilemeyen SOS'u saymaz**. Sesli
   "yardım" her zaman erişilebilir kalır (sınırdan etkilenmez).
11. **"Yardım" tekrarı = hemen gönder ([sendNow]) koruması:** Geri sayımın
   ilk 2 saniyesinde ([SosConfig.sendNowGuard]) gelen bir `sendNow` isteği
   sayılmaz. Gerekçe: tetikleyici "yardım" cümlesinin kendisi bir
   dinleme oturumunda tanınır; SOS geri sayımı hemen ardından SESSİZ yeni
   bir dinleme oturumu açar ([VoiceController.listenForSos]). Konuşma
   tanıyıcı aynı sonucu (eski oturumun "final"i) geç ya da yinelenerek
   bildirirse, bu yeni oturuma karışmasın diye her `_listen` çağrısı bir
   oturum numarası alır; callback'ler yalnızca kendi oturum numaraları hâlâ
   güncelse işlenir (`VoiceController._sessionSeq`). İki koruma birlikte:
   numara eski oturumun sonucunu tamamen eler, süre koruması da aynı anda
   söylenen gerçek bir tekrarın kazara "hemen gönder" sayılmasını geciktirir.
12. **SOS geçmişi yalnızca isim ve sonuç durumu:** `SosController.history`
   ve `AppState.log`'a yazılan SOS satırları telefon numarası ve konum
   (koordinat, Haritalar bağlantısı, doğruluk) **hiçbir zaman içermez**;
   yalnızca "Ayşe Demir arandı", "SMS: 2/2 kişiye gönderildi" gibi. Bellekte
   en fazla `SosController.maxHistory` (20) satır. Testle kilitli
   (`sos_test.dart` "geçmiş" grubu).
13. **Acil kişi listesi Android otomatik yedeğine girmez.** Numaralar
   `Context.getNoBackupFilesDir()` içinde saklanır (kanal
   `patika/emergency_contacts`, `EmergencyContactsStorage.kt`,
   `SecureFileEmergencyContactStore`) - Android'in bu tür veriler için
   dokümante ettiği yol; bulut yedeğine ve cihazdan cihaza aktarıma hiç
   girmez, ayrı bir yedek kuralı (XML) ya da yeni paket gerekmez. Diğer
   veriler (ayarlar, takma adlar) olağan `SharedPreferences`'ta kalıp
   yedeklenmeye devam eder.
   **Şifreli depolama değerlendirildi, kurulmadı:** `flutter_secure_storage`
   (Android Keystore) ek koruma sağlardı ama (a) adreslenen asıl tehdit
   (bulut/hesap ele geçirme) `noBackupFilesDir` ile zaten kapanıyor,
   (b) cihaz kökse uygulamanın kendisi de anahtara erişebildiği için ek
   şifreleme çoğu senaryoda sınırlı fayda sağlar, (c) yeni bağımlılık ve
   bakım yükü. Sonra istenirse eklenebilir - **paket kurulmadan önce onay
   gerekir** (proje kuralı).
   **Cihazda doğrulanmadı**, bekleyen telefon testlerine eklendi: gerçek
   bir yedek alıp geri yüklendiğinde acil kişilerin gelmediği, ayarların
   geldiği kontrol edilecek.
14. **Acil kişi kurulumu (7a-3):** sesle "acil kişi ekle X" telefon
   rehberinden çözer (`RecipientFlow`, isim yoksa/belirsizse sorar), onaydan
   sonra eklenir. Numara her zaman kişinin rehberdeki **ilk** numarası.
   SMS izni **yalnızca `direct` derlemesinde ve kurulum sırasında** sesli
   açıklamayla istenir - SOS anında değil (SOS yalnızca yoklar,
   `SosPermissions`). İzin verilirse **isteğe bağlı**, yalnızca `direct`de
   bir rıza SMS'i sorulur ("... acil kişiniz olarak eklendi" bildirimi);
   `play`'de SMS izni hiç istenmez, rıza sorusu hiç sorulmaz. "acil kişi
   sil X" **telefon rehberine değil kayıtlı acil kişilere** karşı çözülür
   (`ContactMatcher` yeniden kullanılır, isim yoksa/bulunamazsa mevcut
   kişiler söylenir). "acil kişiler kim" diyalogsuz tek adımda okur.
   Testlerde gerçek SMS/arama gitmez (`FakeDirectActions`, 112 koruması).

## Faz 7b kararları (pil + durum; geçerli, tekrar tartışma)

1. **Pil yalnızca uyarır, hiçbir şeyi durdurmaz.** Kritik pilde bile SOS,
   navigasyon ya da arka plan servisi kendi kendine kapanmaz ("yardım etmeyi
   keseyim" kararını sistem vermez). `battery_wiring_test.dart` kilitler.
2. **Telefon pili:** kendi kanalımız (`patika/battery`, `BatteryProbe.kt`),
   `battery_plus` değil (yeni bağımlılık yok). Sticky `ACTION_BATTERY_CHANGED`,
   izin gerekmez; Dart 30 sn'de bir yoklar (`BroadcastReceiver` değil: motor
   etkinlikten ayrık, ek ömür yönetimi istemedik). Okunamazsa "bilinmiyor",
   değer uydurulmaz.
3. **Eşikler:** telefon %30/%15/%5, gözlük %20/%10/%5. Her eşik bir kez;
   eşiğin +5 puan üstüne çıkınca yeniden kurulur (gözlük her %1'de yazar).
   İlk okuma eşiğin altındaysa tek cümle. %5'te 5 dk'da bir **yalnızca
   titreşim** hatırlatması. Şarjdayken düşük pil uyarısı yok.
4. **Öncelik:** düşük/kritik pil `high` (`critical` SOS ve engel için).
   Şarj olayları ("şarja takıldı", "doldu") `low`, `say` ile, **titreşimsiz**
   (`signal` titreşimi kuyruğa bakmadan çalar); kritik ya da normal bir
   duyurunun önüne geçmez, bayat kalırsa (10 sn) atılır. Gözlükte şarj durumu
   protokolde yok, şarj olayı üretilmez.
5. **Meşgul kuralı:** SOS geri sayımı/gönderimi, SOS'un başlattığı arama
   (`SosController.callInProgress`), gelen arama ve karşıya geçiş
   duraklamasında düşük pil uyarısı konuşmaz, **ertelenir**; meşguliyet bitince
   SOS duyurusundan **ayrı, sıralı** bir duyuru olarak gelir (testle kilitli).
   Şarj olayı ve hatırlatma ertelenmez, atılır. Pil olayları işlem geçmişine
   yazılmaz.
6. **DURUM niyeti:** "durum", "durum ne", "pil", "pil(im) ne kadar (kaldı)",
   "gözlüğün pili kaç" - yalnızca **tüm cümle**; SOS ve DUR'dan sonra, "ne
   kadar kaldı"dan önce denetlenir ("acil durum" SOS; "hava durumu" tanınmaz,
   Katman 2'nin işi). Dikte sırasında hiç denetlenmez (diyalog cevabı sınıflandırıcıya
   gitmez). "Pil" ayrı niyet değil, aynı özet.
7. **Durum özeti (seçenek 2):** SOS sürüyorsa en başta; gözlük bağlı mı +
   pili; telefon pili (+ şarj); navigasyon (çalışıyor + "ne kadar kaldı"
   cümlesi / karşıya geçiş duraklaması / yok). **Geçmiş SOS özeti yok**
   (bellekteki geçmiş kalıcı değil, yanıltıcı olabilir). Bağlı değilken eski
   gözlük pili söylenmez. Yasaklı kelime testi Pil ve Durum bölümlerini tarar.

**Risk kaydı (`patika/CLAUDE.md`):** Z20 (telefon IMU'su ile düşme
algılama) düşme algılama kaldırıldığı için **KAPATILDI (2026-10-01)**.
Elle tetiklenen SOS'un yanlış alarmı ayrı bir risk olarak **Z21**'de
izleniyor (geri sayım + iptal varsayılanı GÖNDER, Faz 7 kararları madde 2).

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

Faz 1–7b yapıldı; faz planı **7b ile sona erer**. Faz 6 ve Faz 7a/7b ilk
şartnameye göre; aşağıdaki fazlar iptal edildi.

**Faz 7c (Düşme algılama) İPTAL EDİLDİ (2026-10-01)** - telefon IMU
güvenilirliği düşük (cepte/çantadayken gerçek düşme, telefonun düşmesinden,
oturmadan ya da sert hareketten güvenilir ayrılamıyor; yanlış pozitif/negatif
riski yüksek), gerçek kullanıcı araştırmasında (Altınokta Körler Derneği) bu
özellik hiç talep edilmedi, ana misyonla (güvenli navigasyon, proaktif engel
tespiti) doğrudan bağlantısı zayıf: tepkisel bir özellik, önleyici değil.
Gölge modu ve açık mod, Kotlin tarafı (`MotionProbe.kt`,
`FallShadowLogStorage.kt`, `FallOpenConsentStorage.kt`), `lib/fall/`, ilgili
testler ve `docs/fall_*` kaldırıldı; kod ve plan git geçmişinde (7c-1
`a4c49b5`, 7c-2 `c632967`/`124b93b`). Telefonda eskiden kalmış gölge kaydı ve
onay dosyaları (`noBackupFilesDir`) için temizlik kodu eklenmedi (uygulama
verisi silinince gider). `SosSource.fall`, `FallSosBridge` ve
`SosController.onOutcome` kaldırıldı; elle SOS (Faz 7a) aynen duruyor.

**Faz 8 (Hava durumu, haber, müzik) İPTAL EDİLDİ (2026-10-01)** - hava
durumu Gemini/Katman 2 (Python) üzerinden zaten doğal dille sorulabiliyor,
konum servisleri açıkken gerçek veri alınabiliyor; Flutter'da ayrı bir
yer tutucu kod tekrarı olurdu. Haber okuma ve müzik kontrolü ana misyonla
ilgisiz. `PatikaIntent.hava/muzik/haber`, sesli komut kalıpları, handler'lar
ve "henüz hazır değil" metinleri kaldırıldı; gözlükten `HAVA`/`MÜZİK`/`HABER`
gelirse `bilinmiyor`'a düşer (bu işlevler Katman 2'nindir).

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
(`ocr_handler.dart`) yer tutucu olarak kalıyor. `frm` komutu ayrılmış
kalıyor: taslak tanımı "kamera akışını başlat/durdur" (aşağıda, Donanım
kararları); firmware'de netleşecek.

## Donanım kararları (2026-09-28)

1. **Gözlükte titreşim motoru yok** (tasarımdan çıkarıldı). Gözlüğe titreşim
   gönderen kod ve protokol satırları (`hap`, `GlassesHaptics`,
   `sendHapticPattern`, `encodeHaptic`, `wireId`, `CompositeHaptics`, yön
   desenleri) kaldırıldı. Telefonun kendi titreşimi (`PhoneHaptics`) kalır.
2. **Engel uyarısı: gözlükte yerel earcon** (ESP32 flash'ı, ~50 ms, telefona
   sormadan; 5 koşullu AND eşiği, telefon yalnızca susturabilir). Karar
   `patika/MIMARI.md` ("Yerel earcon eşiği") ve `patika/NOTES.md`
   (2026-09-17 revizyonu, karar 2) kaynaklı; **firmware'de doğrulanacak**.
   `ble_protocol.md` §5 buna göre hizalandı. Açık: zon susturma mesajının
   biçimi, eşik değerleri. Zemin/baston menzili engelleri earcon kapsamında
   değil, telefondan sesle.
3. **Kamera:** gözlük Wi-Fi SoftAP açar; MJPEG (HTTP) görüntü, WebSocket
   ses ve kontrol. Tespit ve karar mantığının tamamı telefonda. `frm`
   taslağı: akışı başlat/durdur (`ble_protocol.md` §7). Henüz kodlanmadı.
4. Antigravity artık kullanılmıyor; testleri ve dokümanı Claude Code
   yazıyor (bu repoda kalıntı yok; `patika` reposu ayrıca temizlenecek).
