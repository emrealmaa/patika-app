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
         (TTS, öncelik)  (telefon+gözlük) (kısa ses)
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
| **DialogManager** | `lib/voice/dialog_manager.dart`, `lib/voice/dialogs/` | Çok adımlı sesli akışlar (ARA, MESAJ): kişi eksikse sorar, "iki Ahmet var, hangisi?", onay ("Ahmet Kaya'yı arayayım mı?"), mesaj dikte + geri okuma + düzelt. Soru bitince tetikleyici beklemeden dinler; "dur"/"tekrar et" her adımda; cevapsız soru bir kez tekrarlanır, sonra iptal. SOS diyaloğu keser. |
| **Kişi eşleştirme** | `lib/contacts/` | Söylenen adı rehberdeki kişiye çözer (ARA/MESAJ/NUMARA). Bkz. aşağıdaki bölüm. |
| **PatikaBleService** | `lib/ble/patika_ble_service.dart` | Gözlük arayüzü: bağlantı durumu, komut, buton, jest, pil, heartbeat akışları; titreşim gönderme. Gerçek (`RealBleService`) ve simülasyon (`SimulatedBleService`) uygulamaları birbirinin yerine geçer. |
| **GlassesProtocol** | `lib/ble/glasses_protocol.dart` | JSON mesaj ayrıştırma ve kodlama. Bkz. [ble_protocol.md](ble_protocol.md). |
| **ConnectionSupervisor** | `lib/ble/connection_supervisor.dart` | Açılışta otomatik bağlanma (son cihaz, yoksa tek bulunan gözlük), heartbeat izleme (6 sn), üstel geri çekilmeli yeniden bağlanma, 3 başarısızlıktan sonra tek uyarı. "Bağlı" ile "sağlıklı" ayrı tutulur. |
| **BackgroundService** | `lib/background/foreground_service.dart` | Android foreground service. Yalnızca süreci canlı tutar, iş yapmaz. Mantık ana isolate'te kalır. Kalıcı bildirim: "Patika gözlüğe bağlı". |
| **FeedbackHub** | `lib/accessibility/feedback_hub.dart` | Kullanıcıya giden tüm geri bildirimin tek kapısı. Olay → titreşim deseni + kısa ses + konuşma. Ayarları (şiddet, bildirim türü, ayrıntı) tek yerde uygular. |
| **AnnouncementQueue** | `lib/accessibility/announcement_queue.dart` | Öncelikli TTS kuyruğu (`low` < `normal` < `high` < `critical`). Yüksek öncelik konuşulanı keser, 3 sn içindeki tekrarlar birleştirilir, bayat `low` duyurular atılır. `repeatLast`/`stopAll` Faz 2'deki "tekrar et"/"dur" için. |
| **HapticPatterns** | `lib/accessibility/haptic_patterns.dart` | Ritimle ayrışan 10 desen. Park sensörü mantığında engel aralığı. `PhoneHaptics`, `GlassesHaptics` ve ikisini birleştiren `CompositeHaptics`. |
| **Earcon** | `lib/accessibility/earcons.dart` | 4 kısa ses. Dosyalar `tool/generate_earcons.dart` ile üretiliyor. |
| **PermissionExplainer** | `lib/permissions/permission_explainer.dart` | "Önce sesli açıkla, sonra sor": izin penceresinden önce neden gerektiği TTS ile söylenir. |
| **Settings** | `lib/settings/` | Konuşma hızı ve tonu, sessizlik süresi (1–6 sn), ayrıntı, titreşim şiddeti, bildirim türü. Ayarlar sesle de değişir (AYAR niyeti). |
| **Tr** | `lib/l10n/strings_tr.dart` | Kullanıcıya giden tüm Türkçe metinler. |
| **SentMessageLog** | `lib/commands/sent_messages.dart` | "Gönderdiğim son mesajı oku". Yalnızca bellekte. `play` türünde gönderim doğrulanamadığı için "hazırlanan son mesaj" denir. |
| **DirectActions** | `lib/platform/direct_actions.dart`, `android/.../DirectActions.kt` | Onaydan sonra doğrudan arama (`TelecomManager.placeCall` - ekran başlatmaz, kilitli ekranda da çalışır) ve SMS (tüm parçalar operatöre ulaşınca "gönderildi"). Yalnızca `direct` derleme türünde; `play` türünde arama/SMS ekranı açılır. |

## İlkeler

- **Simülasyon önce:** Her gözlük özelliği önce `PatikaBleService` arayüzüne,
  sonra `SimulatedBleService`'e eklenir ve Test Modu'ndan tetiklenebilir.
- **Tek sesli çıkış:** Duyurular TalkBack'e değil TTS'e gider. TalkBack
  yalnızca ekrandaki `Semantics` etiketlerini okur. Böylece çift okuma olmaz.
- **Her sonuç ses + titreşim:** `FeedbackHub.result`.
- **Asla çökme:** Platform eklentisi hataları (plugin yok, izin yok) yakalanır.
  Bozuk BLE mesajları atlanır.
- **Sessiz kopma yok:** Bağlantı kaybı `high` öncelikle duyurulur. Engel
  uyarısı ise gözlükte, telefondan bağımsız çalışır (bkz. protokol §5).

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
