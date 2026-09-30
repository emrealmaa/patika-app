# Mimari

Patika companion app, görme engelli kullanıcı için **ekrana bakmadan**
kullanılacak şekilde tasarlanıyor. Her karar "ekransız çalışır mı?" sorusuna
göre veriliyor.

## Akış

```
 Gözlük butonu / jest   Konuş sekmesi   Hızlı Ayarlar karosu
             └──────────────┼──────────────┘
                   VoiceController.startListening()
                            │  SpeechInputService
                            │  classifyVoiceCommand
 Gözlük (BLE cmd)           │                      Test Modu (elle)
      │                     │                            │
      ▼                     ▼                            ▼
               BleCommand (intent + entity)
                           │
                  AppState._process()
                           │
                     CommandRouter ──► *Handler ──► ActionResult
                           │
                      FeedbackHub.result()
               ┌───────────┼─────────────┐
       AnnouncementQueue  HapticOutput  EarconPlayer
         (TTS, öncelik)   (telefon)     (kısa ses)
```

## Modüller

| Modül | Dosya | Görevi |
|---|---|---|
| **VoiceController** | `lib/voice/voice_controller.dart` | Tüm tetikleyicilerin tek dinleme kapısı. Aç/kapat; dinlemeden önce TTS'i susturur (tetikleyiciyle araya girme); mikrofon iznini sesli açıklamayla ister; kontrol komutlarını ("dur", "tekrar et") teyitsiz uygular. |
| **Sınıflandırıcı** | `lib/commands/voice_intent_classifier.dart`, `intent_lexicon.dart` | Tamamen yerel. Önce katı katmanlar (kontrol/SOS, ayar, takma ad, son mesaj), sonra ağırlıklı anahtar kelime puanlaması (tablo `intent_lexicon.dart`'ta). Günlük söyleyiş çeşitliliği tabloya kelime eklenerek karşılanır. |
| **RecognitionSession** | `lib/voice/recognition_session.dart` | Tek dinleme oturumunun sonucunu bir kez teslim eder. `partialResults` açık: "final" gelmese de son tanınan metin kullanılır; "bitti"den sonra gelen geç sonuç için 1 sn bekler (Galaxy S24 FE'de görüldü). |
| **LaunchActions** | `lib/platform/launch_actions.dart`, `android/.../ListenTileService.kt` | Hızlı Ayarlar karosu → "dinle". Talimat native tarafta bekletilir (kanal `patika/launch`), Dart hazır olunca alır; ilk açılışta da kaybolmaz. |
| **Tutorial** | `lib/tutorial/tutorial.dart` | Sesli eğitim. Yüksek öncelikli bir duyuruyla kesilen adımı tekrar okur (`AnnouncementQueue.add` → `Future<bool>`). "Dinlendi" bilgisi ayarlardan ayrı saklanır. |
| **ControlHandler** | `lib/commands/handlers/control_handler.dart` | DUR / TEKRAR / KOMUTLAR / EĞİTİM / SOS (yer tutucu). `ActionResult.silent` ile "dur"un sonucu okunmaz. |
| **DialogManager** | `lib/voice/dialog_manager.dart`, `lib/voice/dialogs/` | Çok adımlı sesli akışlar (ARA, MESAJ): kişi eksikse sorar, "iki Ahmet var, hangisi?", onay ("Ahmet Kaya'yı arayayım mı?"), mesaj dikte + geri okuma + düzelt. Soru bitince tetikleyici beklemeden dinler; "dur"/"tekrar et" her adımda; cevapsız soru bir kez tekrarlanır, sonra iptal. SOS diyaloğu keser (dikte sırasında yalnızca TÜM cümle SOS ise - DUR/TEKRAR gibi; aksi halde mesaj içeriğinde "yardım" gibi kelimeler geçince mesaj kaybolurdu). |
| **Kişi eşleştirme** | `lib/contacts/` | Söylenen adı rehberdeki kişiye çözer (ARA/MESAJ/NUMARA). Bkz. aşağıdaki bölüm. |
| **PatikaBleService** | `lib/ble/patika_ble_service.dart` | Gözlük arayüzü: bağlantı durumu, komut, buton, jest, pil, heartbeat akışları. Gerçek (`RealBleService`) ve simülasyon (`SimulatedBleService`) uygulamaları birbirinin yerine geçer. |
| **GlassesProtocol** | `lib/ble/glasses_protocol.dart` | JSON mesaj ayrıştırma ve kodlama. Bkz. [ble_protocol.md](ble_protocol.md). |
| **ConnectionSupervisor** | `lib/ble/connection_supervisor.dart` | Açılışta otomatik bağlanma (son cihaz, yoksa tek bulunan gözlük), heartbeat izleme (6 sn), üstel geri çekilmeli yeniden bağlanma, 3 başarısızlıktan sonra tek uyarı. "Bağlı" ile "sağlıklı" ayrı tutulur. |
| **BackgroundService** | `lib/background/foreground_service.dart` | Android foreground service. Yalnızca süreci canlı tutar, iş yapmaz. Mantık ana isolate'te kalır. Kalıcı bildirim: "Patika gözlüğe bağlı". |
| **FeedbackHub** | `lib/accessibility/feedback_hub.dart` | Kullanıcıya giden tüm geri bildirimin tek kapısı. Olay → titreşim deseni + kısa ses + konuşma. Ayarları (şiddet, bildirim türü, ayrıntı) tek yerde uygular. |
| **AnnouncementQueue** | `lib/accessibility/announcement_queue.dart` | Öncelikli TTS kuyruğu (`low` < `normal` < `high` < `critical`). Yüksek öncelik konuşulanı keser, 3 sn içindeki tekrarlar birleştirilir, bayat `low` duyurular atılır. `repeatLast`/`stopAll` Faz 2'deki "tekrar et"/"dur" için. |
| **HapticPatterns** | `lib/accessibility/haptic_patterns.dart` | Ritimle ayrışan 10 desen, yalnızca telefonda (`PhoneHaptics`): gözlükte titreşim motoru yok. Park sensörü mantığındaki engel aralığı yalnızca telefon simülasyonudur; gerçek engel uyarısı gözlükte yerel earcon'dur (bkz. ble_protocol.md §5, firmware'de doğrulanacak). |
| **Earcon** | `lib/accessibility/earcons.dart` | 4 kısa ses. Dosyalar `tool/generate_earcons.dart` ile üretiliyor. |
| **PermissionExplainer** | `lib/permissions/permission_explainer.dart` | "Önce sesli açıkla, sonra sor": izin penceresinden önce neden gerektiği TTS ile söylenir. |
| **Settings** | `lib/settings/` | Konuşma hızı ve tonu, sessizlik süresi (1–6 sn), ayrıntı, titreşim şiddeti, bildirim türü. Ayarlar sesle de değişir (AYAR niyeti). |
| **Tr** | `lib/l10n/strings_tr.dart` | Kullanıcıya giden tüm Türkçe metinler. |
| **SentMessageLog** | `lib/commands/sent_messages.dart` | "Gönderdiğim son mesajı oku". Yalnızca bellekte. `play` türünde gönderim doğrulanamadığı için "hazırlanan son mesaj" denir. |
| **DirectActions** | `lib/platform/direct_actions.dart`, `android/.../DirectActions.kt` | Onaydan sonra doğrudan arama (`TelecomManager.placeCall` - ekran başlatmaz, kilitli ekranda da çalışır) ve SMS (tüm parçalar operatöre ulaşınca "gönderildi"). Yalnızca `direct` derleme türünde; `play` türünde arama/SMS ekranı açılır. |
| **PatikaCallService** | `lib/platform/call_service.dart`, `simulated_call_service.dart` | Gelen arama durumu (Faz 4b). `PatikaBleService`'ten bilerek ayrı: BLE değil, telefonun kendi yeteneği (DirectActions/SentMessageLog gibi). Çalmaya başlayınca yüksek öncelikle "$ad arıyor" duyurulur; gözlük butonunun dokunma/uzun basış anlamı o sırada değişir (`AppState._onButton`): dokunma açar, uzun basış reddeder - SOS yalnızca sesle erişilebilir olur. Gerçek uygulama (`PatikaNotificationListener.kt` + `NotificationListenerService`) henüz yazılmadı; şimdilik yalnızca `SimulatedCallService` var, Test Modu'ndan tetikleniyor. |
| **SOS (Faz 7)** | `lib/sos/` | Acil durum. `SosController`: tetikle -> ön kontrol -> geri sayım (elle 7 sn, düşme 25 sn; iptal yoksa GÖNDERİR) -> SMS hepsine -> sonuçlar söylenir -> tek arama. Konum geri sayım BAŞLARKEN aranır. Düşmede 112 kendiliğinden aranmaz; SMS sonuçlarından sonra 6 sn'lik "112 için çift dokunun" penceresi (çift dokunuş `AppState._onSosButton`'da onay sayılır). Arama başladıktan sonra TTS konuşmaz (`AudioModeCallMonitor`: `AudioManager.getMode()`, izin gerekmez; bitiş doğrulanamazsa hiç konuşulmaz, yalnızca geçmişe yazılır). `DirectSosDelivery` yalnızca `direct` derlemesinde; `play`'de ön kontrol "desteklenmiyor" der. `EmergencyNumber`: release'te 112 sabit, release dışında yalnızca `PATIKA_SOS_TEST_NUMBER`. `FeedbackSosAnnouncer` söyleyenler; `SosCountdownBanner` telefon ekranından iptal. Sesli iptal: `VoiceController.listenForSos` sessiz oturum + oturum numarası (eski oturumun yinelenen sonucu yeni oturuma karışmaz) + `classifySosVoice` (yalnızca iptal/gönder; "dur" iptal etmez; "yardım" tekrarı ilk 2 sn sayılmaz). `SosController.history`: yalnızca isim ve sonuç durumu, telefon numarası/konum hiç yazılmaz. Acil kişi listesi `Context.getNoBackupFilesDir()`'da (yedeğe girmez, `SecureFileEmergencyContactStore`). |
| **Acil kişi kurulumu (Faz 7a-3)** | `lib/voice/dialogs/emergency_contact_flow.dart`, `lib/commands/handlers/emergency_contact_handler.dart` | "acil kişi ekle/sil X", "acil kişiler kim" (niyet `acilKisi`, katı ayrıştırma `voice_intent_classifier.dart`da `_emergencyContactCommand`). Ekleme rehber üzerinden ([RecipientFlow], isim yoksa sorar, belirsizse "hangisi?"), onaydan sonra `direct` derlemesinde SMS izni **kurulum sırasında** istenir (SOS anında değil) ve verilirse isteğe bağlı, yalnızca `direct`de giden bir rıza SMS'i sorulur. Silme kayıtlı acil kişiler arasında (`ContactMatcher` yeniden kullanılır, telefon rehberi değil). Liste diyalogsuz tek adımda okunur. |
| **Navigasyon (Faz 6)** | `lib/navigation/` | Saf mantık ve bağlantısı. `guidance_engine.dart`: konum → olay durum makinesi (dönüş duyuruları 50/15 m, varış, rota dışı + histerezis, konum belirsiz, karşıya geçiş duraklaması 90 sn üst süreli, hareket yönünden yön teyidi); eşikler `GuidanceConfig`'de. `guidance_speech.dart`: olay → bilgi kipi cümlesi (Google'ın talimat metni asla seslendirilmez). `navigation_session.dart`: motor + konum akışı + ticker + FeedbackHub + yeniden rota. `google_client.dart`/`google_parsing.dart`: Routes/Places (anahtar `--dart-define`, yoksa kurulmaz). `navigation_backend.dart`: yeri çöz → rota → onay → başlat; her adımda başarısızlık Google Haritalar yedeğine düşer ve nedeni söylenir. |
| **NavigationFlow** | `lib/voice/dialogs/navigation_flow.dart` | NAVİGASYON diyaloğu: yer sor → "hangisi?" → onay. `NavigationHandler` başlatır. |
| **Konum** | `lib/platform/location_service.dart`, `lib/permissions/location_access.dart` | `PatikaLocationService` (gerçek: `geolocator`; simülasyon). Konum izni melez akışla: eğitimin sonunda sesli açıklamayla; reddeden/atlayan için ilk navigasyonda, yalnızca uygulama ön plandaysa. Arka plan servisi izin varsa ve uygulama görünürken konum türüyle (re)başlar; `ACCESS_BACKGROUND_LOCATION` yok. |
| **IncomingMessages / IncomingMessageLog** | `lib/platform/incoming_messages.dart`, `lib/commands/incoming_message_log.dart` | Bildirimden yakalanan mesajlar (Faz 4b, gerçek yakalama: `PatikaNotificationListener.kt`). `AppState._onIncomingMessage` her mesajı (susturulmuş olsa bile) günlüğe ekler; ayar açıksa içeriği okur (ilk kez `LoudMessagesNotice` ile bir kerelik gizlilik uyarısı), kapalıysa yalnızca göndereni söyler. MESAJLARIM/SON_BİLDİRİMLER niyetleri (`MessageHistoryHandler`) aynı günlüğü sırasıyla "okunmamışları oku" ve "son 20'nin göndereni" için okur; AYAR'daki `notificationsMuted` yalnızca duyuruyu susturur, günlüğü değil. |
| **Pil + Durum (Faz 7b)** | `lib/battery/`, `android/.../BatteryProbe.kt`, `lib/commands/handlers/status_handler.dart` | Telefon pili 30 sn'de bir yoklanır (kanal `patika/battery`, sticky `ACTION_BATTERY_CHANGED`, izin yok); gözlük pili `batt` mesajından. `BatteryMonitor` eşikleri (telefon 30/15/5, gözlük 20/10/5, +5 histerezis), %5'te 5 dk'da bir yalnızca titreşim. SOS/arama/karşıya geçiş sırasında uyarı ertelenir. Şarj olayları `low` öncelik, titreşimsiz. **Yalnızca uyarır, hiçbir şeyi durdurmaz.** DURUM niyeti ("durum", "pil ne kadar"): gözlük + iki pil + navigasyon özeti. |
| **Düşme algılama - gölge (Faz 7c-1)** | `lib/fall/`, `android/.../MotionProbe.kt`, `FallShadowLogStorage.kt`, `docs/fall_detection_plan.md` | Gölge modu: yerel kayıt, **hiçbir mesaj göndermez, SOS'u tetiklemez** (yalnızca açık mod, aşağıdaki satır, tetikler; `lib/fall/` SOS'u hiç bilmez, testle kilitli). `MotionProbe.kt` ivmeölçeri ~50 Hz verir (kendi kanalımız, `sensors_plus` yok). `FallDetector`: eşik tabanlı 4 adım (serbest düşüş, darbe, yön değişimi, hareketsizlik); **eşikler tamamen tahminidir** (`FallConfig`), gölge verisiyle ayarlanacak. `FallCandidateSource` arayüzü gözlük IMU'suna açık (`PhoneImuFallCandidateSource` bugünkü tek uygulama). `FallShadowLog`: `noBackupFilesDir`'da en fazla 200 kayıt / 14 gün, yalnızca darbe adımına ulaşanlar, konum ve ham sensör verisi yok. Debug derlemesinde varsayılan gölge, release'te kapalı. Test Modu'nda mod anahtarı, sentetik sinyal düğmeleri (ayrı `synthetic` kaynak), kayıt listesi. "durum" komutuna tek cümle (yalnızca mod kapalı değilse). |
| **Düşme algılama - açık mod (Faz 7c-2)** | `lib/fall/`, `lib/sos/fall_sos_bridge.dart`, `lib/voice/dialogs/fall_enable_flow.dart`, `lib/widgets/fall_enable_dialog.dart`, `FallOpenConsentStorage.kt`, `docs/fall_open_mode_plan.md` | Deneysel, opt-in. **İki adımlı açma** (`FallEnableSession`): adım 1 kapıları (`FallOpenModeGate`: `direct` derleme, acil kişi, SMS izni, gölge >= 7 gün kesintisiz) denetler ve uyarıyı okutur, modu AÇMAZ; adım 2 yalnızca adım 1'in kanalından (ses: "anladım, aç" kalıpları, ekran: pencere düğmesi) ve 120 sn içinde kabul edilir, kapılar onay anında yeniden denetlenir. Ekran (Ayarlar "Düşme algılama (deneysel)") ve ses AYNI oturumu paylaşır. **Silah**: ayar dosyasındaki `on` tek başına yetmez; `FallSosBridge` yalnızca bu oturumda silahlıysa tetikler. Onay **bu cihazda** `noBackupFilesDir`'deki dosyadadır (yedekten/cihaz aktarımından gelmez); açılışta `on` + onay yok ya da bir kapı bozuk ise mod KENDİLİĞİNDEN gölgeye düşer ve SESLE söylenir (son acil kişi silinince de). `FallSosBridge` (tek yer, `SosSource.fall`): sentetik kaynak asla; iptalden 2 dk bastırma (bellekte, yalnızca düşme); süren SOS/arama kesilmez; sıradan diyalog ve dinleme kesilir; `SosController.trigger(fall)` (25 sn, 112 kendiliğinden aranmaz). Geri sayımda kalan 15 ve 5 sn'de kısa tekrar duyuru (konuşurken mikrofon kapalı: kendi "iptal" sesimiz SOS'u iptal etmesin). Gölge kaydına `act` etiketi: `none`/`started`/`cancelled`/`sent`/`suppressed`. `SosController.onOutcome` yalnızca bilgi verir. "Kapat" (sesli, gölge anahtarı) tam kapatır ve gölge sayacını sıfırlar; ekrandaki "Açık modu kapat (gölge modu sürer)" yalnızca gölgeye düşürür. Debug'da 7 gün kapısı `--dart-define=PATIKA_FALL_SKIP_SHADOW_GATE=true` ile atlanır ve iz bırakır. |

## Gözlük kanalları (planlanan)

- **BLE:** kontrol, buton, jest, pil, ToF, heartbeat (bkz.
  [ble_protocol.md](ble_protocol.md)). Gözlükte titreşim motoru yok.
- **Wi-Fi SoftAP:** gözlük kendi erişim noktasını açar, telefon bağlanır.
  Kamera MJPEG (HTTP), ses ve kontrol WebSocket ile akar. Tespit ve karar
  mantığının **tamamı telefonda** çalışır. Henüz kodlanmadı; `frm`
  (akışı başlat/durdur) taslak (ble_protocol.md §7).
- **Ağ riski:** SoftAP internetsizdir. Routes/Places gibi çağrıların mobil
  veriden gitmesi için uygulamaya özel ağ bağlama (`WifiNetworkSpecifier`)
  gerekecek; cihazda doğrulanacak.

## İlkeler

- **Simülasyon önce:** Her gözlük özelliği önce `PatikaBleService` arayüzüne,
  sonra `SimulatedBleService`'e eklenir ve Test Modu'ndan tetiklenebilir.
- **Tek sesli çıkış:** Duyurular TalkBack'e değil TTS'e gider. TalkBack
  yalnızca ekrandaki `Semantics` etiketlerini okur. Böylece çift okuma olmaz.
- **Her sonuç ses + titreşim:** `FeedbackHub.result`.
- **Asla çökme:** Platform eklentisi hataları (plugin yok, izin yok) yakalanır.
  Bozuk BLE mesajları atlanır.
- **Sessiz kopma yok:** Bağlantı kaybı `high` öncelikle duyurulur. Engel
  uyarısı telefondan bağımsız, gözlükte yerel earcon ile verilir (titreşim
  motoru yok; bkz. protokol §5, firmware'de doğrulanacak).

## Kişi eşleştirme (`lib/contacts/`)

Söylenen ad ("annemi", "Mehmet'in", "Ayse") rehberdeki kişiye üç adımda çözülür:

1. **Kök adayları** (`turkish_stemmer.dart`): Tek bir kök tahmin edilmez; tüm
   makul kökler üretilir ("annemi" → annemi, annem, anne; "Ali" → ali, al) ve
   **rehber karar verir**. Orijinal biçim her zaman aday ve cezasız olduğu için
   "Ali" asla "Al"a düşmez. Kesme işaretinden sonrası her zaman ektir.
2. **Takma adlar** (`alias_store.dart`): Önce bakılır ("annem" → Fatma Yılmaz).
   Sesle tanımlanır: "annemi Fatma Yılmaz olarak kaydet". Yalnızca telefonda saklanır.
3. **Bulanık eşleştirme** (`contact_matcher.dart`): Türkçe karakterler
   sadeleştirilir ("Ayse" → Ayşe), Jaro-Winkler ile tam ad ve ad/soyad
   parçalarına karşı puanlanır. Eşik 0,88. En iyiye 0,03 kadar yakın başka
   kişiler varsa sonuç **belirsiz**dir ("iki Ahmet var"); eşiğin biraz
   altındaki yakın adaylar da sayılır. DialogManager bunu "hangisi?" diye sorar.

Rehber 60 sn önbellekte tutulur (`ContactResolver`). İzin sesli açıklamayla istenir.

**Neden Zemberek değil:** Zemberek bir Java kütüphanesi. Dart sürümü yok,
Android'de platform kanalıyla çalıştırılması ve sözlüğüyle ~20–30 MB eklenmesi
gerekir, açılışı da yavaşlatır. Kişi adları için kural tabanlı kök adayları +
rehberin karar vermesi yeterli.

## Derleme türleri (`play` / `direct`)

Android'de `--flavor` her zaman gerekir (`flutter run --flavor play`).
Uygulama kimliği aynıdır; türler arası geçişte veriler ve izinler korunur.

| Tür | Kısıtlı izinler | Arama / SMS |
|---|---|---|
| `play` (Play Store) | Yok | Onaydan sonra arama ekranı / SMS ekranı (metin dolu) açılır, kullanıcı tuşa basar |
| `direct` (dernek dağıtımı) | `CALL_PHONE`, `SEND_SMS` (yalnızca `android/app/src/direct/AndroidManifest.xml`) | Doğrudan arar / gönderir |

Tek doğruluk kaynağı `BuildConfig.DIRECT_ACTIONS`; Dart bunu `patika/direct`
kanalından sorar. Ayrı bir Dart bayrağı yoktur, bu yüzden tür ile davranış
birbirinden sapamaz. `direct` türünde izin reddedilirse ya da arama/SMS
başlatılamazsa `play` davranışına düşülür ve bu kullanıcıya söylenir.

## İzin mimarisi

Hiçbir izin açılışta toplu istenmez. Her izin **ilk gerektiği anda**,
`PermissionExplainer.ensure(izin, neden)` ile istenir: önce nedeni TTS ile
söylenir, sonra sistem penceresi açılır. Reddedilirse özellik zarifçe
geriler, uygulama çökmez.

| İzin | Ne zaman |
|---|---|
| Bildirim (`POST_NOTIFICATIONS`) | Açılışta (arka plan servisinin kalıcı bildirimi için) |
| Mikrofon | İlk dinlemede (VoiceController) |
| Rehber | İlk ARA / MESAJ / NUMARA'da |
| Bluetooth (+ API ≤30 konum) | Gözlük taraması / bağlanma |
| Arama, SMS (yalnızca `direct`) | İlk doğrudan arama / SMS'te |

Testlerde izin kontrolleri enjekte edilir (`AppState`'in
`ensureCallPermission` / `ensureSmsPermission` parametreleri), gerçek
eklenti çağrılmaz.

## Erişilebilirlik kuralları (ekran)

- Her etkileşimli öğe en az 56 dp, bilgi asla yalnızca renkle verilmez.
- Butonları dıştan `Semantics(excludeSemantics: true)` ile sarmayın:
  TalkBack'te dokunma eylemi kaybolur. Etiket butonun içinde verilir
  (bunu koruyan bir test var).
- Diyalog soruları `dedupe: false` ile kuyruğa eklenir; aksi halde tekrar
  sorulan soru 3 sn birleştirmesine takılıp diyalog kilitlenir.

## Dart motorunun ömrü

Dart motoru (BLE, bağlantı denetçisi, duyurular) **etkinlikten bağımsız**
yaşar (`android/.../MainActivity.kt`). Varsayılan `FlutterActivity` motoru
etkinlikle birlikte yok eder; geri tuşu Dart mantığını öldürüyor ama
arka plan servisi "Patika gözlüğe bağlı" demeye devam ediyordu.

| Olay | Davranış |
|---|---|
| Geri tuşu | Uygulama arka plana alınır (`popSystemNavigator` → `moveTaskToBack`), her şey sürer |
| Sistem etkinliği yok eder (bellek, "Etkinlikleri tutma") | Motor önbellekte yaşar; etkinlik geri gelince aynı motora bağlanır, durum korunur |
| Son uygulamalardan kaydırma | Motor bilerek yok edilir ve servis durdurulur: bildirim asla ölü bir motor için "bağlı" demez |

Motor `Application.onCreate`'te değil, ilk etkinlik açılışında oluşturulur.
Süreç ekransız başlarsa (örn. Hızlı Ayarlar karosu bağlanırken) uygulama
kendi kendine bağlanıp konuşmaya başlamaz. Dart kodu etkinlik bağlandıktan
sonra başlatılır; bu yüzden açılıştaki izin istekleri etkinliği bulabilir.

## Bilinen sınırlar

- Kullanıcı uygulamayı son uygulamalardan kaydırırsa servis de kapanır
  (`stopWithTask`, **yalnızca manifestte**: `flutter_foreground_task`'ın Dart
  tarafındaki `stopWithTask` seçeneği uygulama görünmez olunca da servisi
  durduruyordu). Bu bilinçli bir tercih: ölü bir süreç için "bağlı"
  bildirimi yanıltıcı olurdu.
- Arka plan servisine mikrofon türü, yalnızca izin zaten verilmişse eklenir
  (Android 14 kuralı).
- Konuşmayı kesme (barge-in) yalnızca tetikleyiciyle yapılır; kulaklıkla
  sürekli dinleyen deneysel araya girme ertelendi.
