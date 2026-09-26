# Mimari

Patika companion app, görme engelli kullanıcı için **ekrana bakmadan**
kullanılacak şekilde tasarlanıyor. Her karar "ekransız çalışır mı?" sorusuna
göre veriliyor.

## Akış

```
 Gözlük (BLE)        Telefon mikrofonu        Test Modu (elle)
      │                      │                        │
 RealBleService /      SpeechInputService             │
 SimulatedBleService          │                        │
      │  GlassesProtocol  classifyVoiceCommand         │
      ▼                      ▼                        ▼
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
