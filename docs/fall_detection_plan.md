# Düşme algılama (Faz 7c) - uygulama planı

Kararlar: `CLAUDE.md` "Faz 7c kararları" (tekrar tartışılmaz). Bu belge
7c-1'in (yalnızca gölge modu) kod planıdır; 7c-2 (açık mod + SOS) ayrıca
planlanacak.

> **Eşikler tamamen tahminidir.** `lib/fall/fall_config.dart`'taki her değer
> literatür ve sağduyudan alınmış bir başlangıç değeridir; hiçbir gerçek
> düşme ya da gerçek kullanım verisiyle doğrulanmamıştır. Gölge verisiyle
> ayarlanacaktır.

## Kesin sınır (7c-1)

Düşme algılama 7c-1'de **hiçbir yoldan** `SosController`'a ulaşmaz.
`FallMode` yalnızca `off` ve `shadow` içerir; `on` 7c-2'de eklenir. Testle
kilitli (`fall_monitor_test`: aday oluşunca SOS hiç çağrılmaz).

## Native

- **`MotionProbe.kt`** (EventChannel `patika/motion`): yalnızca
  `TYPE_ACCELEROMETER`, ~50 Hz (200 Hz altı, izin gerekmez). Örnekler
  Kotlin'de 200 ms'lik paketlerle gönderilir (`[t_ms, x, y, z] × n`, m/s²,
  zaman sensör olay zamanından ms). `onListen` sensörü açar, `onCancel`
  kapatır: sensör yalnızca mod kapalı değilken çalışır. `available`
  sorgusu.
  - **Jiroskop yok:** yön değişimi, düşme öncesi/sonrası yerçekimi
    vektörleri arasındaki açıdan.
  - **Wakelock yok:** ekran kapalıyken CPU uyuyabilir, örnekler kesilebilir.
    Kesinti sayacı (aşağıda) bunu ölçer. İkisi de telefon testinde
    ölçülür, gerekirse eklenir.
- **`FallShadowLogStorage.kt`** (kanal `patika/fall_log`):
  `EmergencyContactsStorage.kt` ile aynı kalıp, `noBackupFilesDir`'da tek
  JSON dosyası. Ayrı sınıf (7a koduna dokunulmaz).
- İkisi `MainActivity.kt`'de birer satırla bağlanır.

## `lib/fall/`

| Dosya | İçerik |
|---|---|
| `fall_config.dart` | `FallConfig`: tüm eşikler (TAHMİNİ), testte değiştirilebilir. |
| `motion_sample.dart` | `MotionSample` (zaman ms, x/y/z m/s², büyüklük g). |
| `fall_detector.dart` | Saf durum makinesi: bekle → serbest düşüş → darbe bekle → yerleşme → gözlem → sonuç. Sonuç: `noImpact`, `noOrientationChange`, `movement`, `candidate` + özet değerler. Örnek kesintisinde sıfırlanır, kesinti sayılır. |
| `synthetic_signals.dart` | Saf sinyal üreticileri (senaryolar). Test Modu düğmeleri ve birim testleri ortak kullanır. |
| `motion_source.dart` | `MotionSource` arayüzü; `MethodChannelMotionSource` (gerçek), `SyntheticMotionSource`. Sentetik örnekler gerçek akışa **karıştırılmaz** (sensör zamanıyla çakışır, kesinti sayılır): ayrı bir `PhoneImuFallCandidateSource(sourceId: 'synthetic')` besler, kayda `synthetic` kaynak adıyla girer; gerçek veri analizinde ayıklanabilir. |
| `fall_candidate_source.dart` | `FallCandidateSource` arayüzü (`evaluations`, `start`/`stop`, `sourceId`). 7c-1'de tek uygulama `PhoneImuFallCandidateSource`. Gözlük IMU'su (TODO.md madde 18) ileride ikinci uygulama olur; dedektör ve kayıt değişmez. |
| `fall_shadow_log.dart` | `FallShadowRecord` (zaman, kaynak, sonuç, özet değerler) + `FallShadowLog`: en fazla 200 kayıt / 14 gün; bozuk dosyada boş liste. `FallLogStore` arkasında (native / bellek). **Konum ve ham örnek alanı yok** (alan beyaz listesi testle kilitli). |
| `fall_mode.dart` | `FallMode { off, shadow }`; `defaultFallMode(isDebug)`: debug → `shadow`, release → `off`. |
| `fall_monitor.dart` | Moda göre kaynağı başlatır/durdurur, sonuçları kayda yazar, test ses işareti açıksa adayda earcon, bellekte kesinti sayacı. Başka hiçbir şey yapmaz. |

**Kayda ne girer (karar):** yalnızca **darbe adımına ulaşan**
değerlendirmeler (`noOrientationChange`, `movement`, `candidate`). Tek başına
serbest düşüş (`noImpact`, ör. telefonu yatağa atmak) günde onlarca olup
200'lük sınırı doldurabilir; yalnızca bellekteki sayaçta sayılır.

**Ayarlar:** `fallMode` (null → derleme türü varsayılanı),
`fallShadowEarcon` (varsayılan false).

**Durum komutu:** `StatusSnapshot.fallMode`; mod kapalı değilse sona tek
cümle.

## Test Modu - "Düşme algılama (gölge)"

Test Modu release derlemesinde de erişilebilir (`lib/main.dart`, sekme
koşulsuz) - bu yüzden gölge anahtarı için ayrı bir ayarlar ekranı yolu
7c-1'de gerekmiyor.

- Mod anahtarı (kullanıcı açınca gölge uyarısı okunur; debug varsayılanı
  olarak açıkken okunmaz), test ses işareti anahtarı.
- Sentetik düğmeler: "Gerçekçi düşme" (aday), "Telefon düştü, hemen
  alındı" (hareket), "Sert oturma" (serbest düşüş yok → değerlendirme
  yok), "Düşüş, darbe yok", "Darbe var, yön değişmedi".
- Kayıt listesi (en yeni üstte, 20 satır, sonuç metinle, Semantics),
  "Kayıtları sil", kesinti sayacı.

## Metinler (onaylandı)

- **Gölge (tam):** "Düşme algılama gölge modunda açıldı. Bu modda hiçbir
  mesaj gönderilmez, acil durum çağrısı başlamaz. Telefon olası düşmeleri
  yalnızca kendi içinde kaydeder, kayıtlarda konum yoktur. Kayıtlar,
  özelliğin ne kadar doğru çalıştığını ölçmek için kullanılacak."
- **Açık (tam, yalnızca ilk kez; 7c-2):** "Düşme algılama deneyseldir. Her
  düşmeyi algılamayabilir, düşme olmayan bir durumu da düşme sanabilir.
  Güvenilmemelidir. Telefon cepte ya da çantadayken doğruluğu düşer. Düşme
  algılanırsa 25 saniyelik geri sayım başlar; iptal edilmezse acil
  kişilerinize mesaj gönderilir, 112 kendiliğinden aranmaz. Açmak için
  'anladım, aç' deyin."
- **Kısa hatırlatma (7c-2):** "Düşme algılama deneysel, hâlâ güvenilmemeli."
- **Durum:** "Düşme algılama gölge modunda, yalnızca kayıt tutuyor."

**İki adımlı açma notu (7c-2 için bağlayıcı):** açık mod metni iki adımı
tek cümlede BİRLEŞTİRMEZ; son cümle yalnızca ikinci adıma köprüdür. Adım 1:
kullanıcı açmak ister → uyarı okunur, mod **açılmaz**. Adım 2: ayrı bir
diyalog turunda yalnızca "anladım, aç" kabul edilir; genel "evet", sessizlik
ya da başka bir cevap açmaz. Ekrandan açmada da anahtar doğrudan açmaz,
ayrı bir onay düğmesi gerekir. Acil kişi yoksa adım 1'de durulur.

## Birim testleri

- `fall_detector_test`: her sentetik senaryo beklenen sonucu verir; eşik
  sınırları (altı/üstü); gürültü; örnek kesintisinde sıfırlama ve sayma;
  yürüme aday olmaz.
- `fall_shadow_log_test`: 200 sınırı, 14 gün budama, bozuk JSON, alan beyaz
  listesi (konum/ham örnek yok).
- `fall_monitor_test`: aday → SOS hiç çağrılmaz; mod değişince kaynak
  açılır/kapanır; earcon yalnızca ayar açıkken; `noImpact` kayda girmez.
- `fall_mode_test`: debug/release varsayılanları.
- `status_command_test`: gölge cümlesi yalnızca mod kapalı değilken.
- Yeni `Tr` bölümü yasaklı kelime taramasına eklenir.

## Uygulama notları (7c-1 kodlanırken netleşenler)

- Sentetik düğmeler ayrı `PhoneImuFallCandidateSource(sourceId: 'synthetic')`
  ve ayrı bir `FallMonitor` ile çalışır (`AppState.runFallScenario`); gerçek
  mod kapalıyken de çalışır (düğmeye basmak açık bir test eylemidir), gerçek
  sensör akışına karışmaz. Her senaryo öncekinden sonra başlar (sensör zamanı
  tek yönde akar; geri giden zaman dedektörde yok sayılır).
- `FallCandidateSource.stop()` abonelik iptalini **beklemez** (abonelik hemen
  kalkar, sensör kapanır): beklemek sırayla işlenen mod değişimlerini native
  onaya bağlıyordu.
- Kesinti sayacı kaynağın ömrü boyunca birikir (durdur-başlat kesinti sayılmaz).
- Kayıtları silmek onay sormaz (Test Modu, kayıt yalnızca ölçüm verisi).

## Sıra

1. `fall_config` + `motion_sample` + `fall_detector` + `synthetic_signals` + testleri
2. Kayıt (Dart + Kotlin)
3. `MotionProbe.kt` + kaynak
4. Monitor + ayarlar + durum
5. Test Modu
6. Belgeler (architecture.md, CLAUDE.md, bekleyen telefon testleri)

## Bitince "Bekleyen telefon testleri"ne

Ekran kilitli ve cepteyken örnek kesintisi (wakelock gerekli mi); pil
etkisi; Galaxy S24 FE'de 50 Hz tutuyor mu; jiroskop gerekli mi; bir hafta
günlük kullanımda gölge kayıtlarının dağılımı (açık mod ölçütü).
