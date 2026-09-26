# Mimari

Patika companion app, görme engelli kullanıcı için **ekrana bakmadan**
kullanılacak şekilde tasarlanıyor. Her karar "ekransız çalışır mı?" sorusuna
göre veriliyor.

## Akış

```
 Gözlük butonu / jest   Konuş sekmesi   (Faz 2b: QS karosu)
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
| **FeatureFlags** | `lib/config/feature_flags.dart` | `--dart-define-from-file` ile verilen bayraklar (Play kısıtlı `CALL_PHONE`/`SEND_SMS` için). |

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
   kişiler varsa sonuç **belirsiz**dir ("iki Ahmet var"). Faz 3b bunu "hangisi?"
   diye soracak.

Rehber 60 sn önbellekte tutulur (`ContactResolver`). İzin sesli açıklamayla istenir.

**Neden Zemberek değil:** Zemberek bir Java kütüphanesi. Dart sürümü yok,
Android'de platform kanalıyla çalıştırılması ve sözlüğüyle ~20–30 MB eklenmesi
gerekir, açılışı da yavaşlatır. Kişi adları için kural tabanlı kök adayları +
rehberin karar vermesi yeterli.

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
  (`stopWithTask`). Bu bilinçli bir tercih: ölü bir süreç için "bağlı"
  bildirimi yanıltıcı olurdu.
- Arka plan servisine mikrofon türü, yalnızca izin zaten verilmişse eklenir
  (Android 14 kuralı). Ekran kilitliyken dinleme Faz 2'de gerçek cihazda
  doğrulanacak.
