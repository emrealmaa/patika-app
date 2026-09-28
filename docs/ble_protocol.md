# Patika Gözlük ↔ Telefon BLE Protokolü

Sürüm: **v1 (taslak)** · Uygulama tarafı: `lib/ble/glasses_protocol.dart`,
`lib/ble/real_ble_service.dart` · Test: `test/glasses_protocol_test.dart`

Bu doküman ESP32-S3 firmware ekibi ile companion app arasındaki sözleşmedir.
Firmware bu repoda değil; burada yazan her şey uygulamanın beklentisidir.

> ⚠️ **UUID'ler henüz placeholder.** Firmware kesinleşince yalnızca
> `real_ble_service.dart` içindeki üç sabit değişecek; mesaj formatı aynı kalır.

## 1. GATT yapısı

Gözlük **peripheral**, telefon **central**.

| Öğe | UUID | Özellik | Yön |
|---|---|---|---|
| Patika servisi | `0000ff10-0000-1000-8000-00805f9b34fb` | — | — |
| Olay karakteristiği | `0000ff11-0000-1000-8000-00805f9b34fb` | `notify` | gözlük → telefon |
| Kontrol karakteristiği | `0000ff12-0000-1000-8000-00805f9b34fb` | `write without response` | telefon → gözlük |

- Gözlük reklamında (advertising) **servis UUID'sini yayınlamalı**. Uygulama
  taramayı bu UUID ile filtreliyor.
- Cihaz adı boş olmamalı (örn. `Patika-XXXX`). İsimsiz cihazlar listelenmiyor.
- Telefon bağlanınca **MTU 247** ister. Yük sınırı buna göre **244 bayttır**.
  MTU pazarlığı başarısız olsa da (23 → 20 bayt) bağlantı sürer. O durumda
  mesajlar 20 bayta sığmalı veya bölünmeden gönderilmemelidir.

## 2. Mesaj formatı

- Her notify/write **tek bir UTF-8 JSON nesnesidir**, satır sonu yok.
- `"t"` alanı mesaj türünü belirtir.
- Uygulama **tanımadığı** türleri ve bozuk mesajları sessizce atlar. Yeni bir
  tür eklemek eski uygulama sürümlerini bozmaz.
- Türkçe karakterler UTF-8 olarak gönderilmelidir (`"NAVİGASYON"`, `"Kadıköy"`).

### 2.1 Gözlük → telefon (olay karakteristiği)

| `t` | Alanlar | Ne zaman | Örnek |
|---|---|---|---|
| `cmd` | `intent` (str), `entity` (str, ops.) | Gözlükte ses → niyet sınıflandırıldığında | `{"t":"cmd","intent":"ARA","entity":"Emre"}` |
| `btn` | `a`: `tap` \| `double` \| `long` | Gözlük butonu | `{"t":"btn","a":"tap"}` |
| `gst` | `g`: `nod2` | IMU jesti (çift baş sallama) | `{"t":"gst","g":"nod2"}` |
| `batt` | `v`: 0–100 (int) | Bağlanınca bir kez, sonra her %1 değişimde | `{"t":"batt","v":76}` |
| `hb` | `seq` (int, ops.) | **Her 2 saniyede bir**, bağlı olduğu sürece | `{"t":"hb","seq":1532}` |

`intent` değerleri Python tarafındaki `intent_classifier.py` ile aynıdır:
`ARA`, `MESAJ`, `HAVA`, `SAAT`, `MÜZİK`, `HABER`, `OKU`, `GECIS_MODU`,
`NAVİGASYON`, `BİLİNMİYOR`.

Geriye dönük uyumluluk: `"t"` alanı olmayan ama `intent` içeren eski format
(`{"intent":"ARA","entity":"Emre"}`) hâlâ `cmd` olarak kabul edilir.

### 2.2 Telefon → gözlük (kontrol karakteristiği)

| `t` | Alanlar | Anlamı | Örnek |
|---|---|---|---|
| ~~`hap`~~ | — | **Kaldırıldı** (gözlükte titreşim motoru yok, bkz. §4) | — |
| `frm` | `on` (bool) | **TASLAK, firmware'de netleşecek.** Kamera akışını başlat/durdur (bkz. §7) | `{"t":"frm","on":true}` |

## 3. Heartbeat ve bağlantı sağlığı

- Gözlük bağlı olduğu sürece **2 saniyede bir** `hb` gönderir.
- Telefon **6 saniye** (3 aralık) boyunca `hb` almazsa bağlantıyı kopmuş sayar,
  keser ve yeniden bağlanmayı dener.
- Bir gözlükten o oturumda **en az bir kez** `hb` geldiyse, sonraki
  bağlantılarda "bağlandı" duyurusu **ilk `hb` gelince** yapılır. BLE
  bağlantısı kurulup `hb` hiç gelmeyen bir bağlantı başarısız deneme sayılır.
  Böylece donmuş bir firmware "bağlandı / koptu" döngüsüne girmez.
- Hiç `hb` göndermeyen bir firmware ile de çalışılır (bağlantı kurulunca
  sağlıklı sayılır), ama o durumda sessiz donma algılanamaz. **`hb` zorunlu
  kabul edilmelidir.**
- Yeniden bağlanma üstel geri çekilmeyle yapılır: 1, 2, 4, 8, 16, 30, 30… sn
  (±%20 rastgele sapma). Art arda **3 başarısız** denemeden sonra kullanıcıya
  bir kez "Gözlüğe bağlanılamıyor, denemeye devam ediyorum" denir.

## 4. Titreşim desenleri

**Kaldırıldı: gözlükte titreşim motoru yok** (tasarımdan çıkarıldı). Telefon
gözlüğe `hap` komutu göndermez; titreşim yalnızca telefonun kendi motorundan
gelir (`lib/accessibility/haptic_patterns.dart`).

## 5. ⚠️ Engel uyarısı: telefondan bağımsız olmalı (AÇIK KARAR: kanal belirlenmedi)

**Engel algılama → kullanıcıyı uyarma döngüsü telefondan bağımsız
çalışmalıdır.** BLE koparsa, telefon kapanırsa, uygulama çökerse veya
telefonun pili biterse kullanıcı **yine de** engel uyarısı almalıdır. Bu
gereksinim geçerli; ancak gözlükte titreşim motoru olmadığı için eski kanal
(gözlükte titreşim) kalktı ve **yeni kanal henüz belirlenmedi.**

Adaylar (karar firmware/donanım tarafıyla netleşecek):

- **Önerilen yön:** ESP32 ToF eşiği aşılınca telefondan bağımsız **yerel kısa
  bip** çalar (kulaklık/earbud). Ayrıntılı cümle ("önünde engel var")
  telefondan gelir.
- **Alternatif (varsayılan, firmware yoksa):** ToF verisi BLE ile telefona
  gider, telefon sesli uyarır. Bu yol telefona ve BLE'ye bağımlıdır; yukarıdaki
  bağımsızlık gereksinimini karşılamaz.

Değişmeyenler:

- ToF sensörü → mesafe → uyarı aralığı hesabı, bağımsız kanal seçilirse
  firmware'de yapılır.
- Önerilen mesafe eşlemesi (park sensörü mantığı; uygulamadaki telefon
  simülasyonuyla aynı): 2,5 m ve ötesi uyarı yok; 0,4 m ve berisi 150 ms
  aralık (neredeyse sürekli); arası 150–1000 ms doğrusal.
- Heartbeat durursa gözlük engel uyarısını **kesmemelidir**.
- Uygulama gözlüğe engel uyarısı komutu göndermez.

## 6. Açık konular

- Gerçek UUID'ler (firmware ile birlikte).
- Engel uyarısı kanalı (§5): gözlükte yerel bip mi, ToF verisi BLE ile
  telefona mı?
- `frm` başlat/durdur mesajının biçimi ve Wi-Fi bilgisinin (SSID/parola,
  IP) nasıl paylaşılacağı (§7). Firmware'de netleşecek.
- Gözlük pil yüzdesinin nasıl hesaplanacağı (voltaj eğrisi) firmware'e ait.
- Protokol sürümü alanı (`"v"`) şimdilik yok. İlk kırıcı değişiklikte
  bağlanınca `{"t":"hello","v":2}` eklenmesi öneriliyor.

## 7. Kamera akışı: Wi-Fi SoftAP (taslak)

BLE yalnızca kontrol, buton, ToF ve pil içindir. Kamera görüntüsü ayrı bir
Wi-Fi kanalından gelir. Bu bölüm **taslaktır; firmware tarafında
netleşecek.**

- **Ağ:** Gözlük kendi Wi-Fi erişim noktasını (**SoftAP**) açar, telefon buna
  bağlanır. Telefonun hotspot'u kullanılmaz.
- **Görüntü:** MJPEG akışı (HTTP).
- **Ses ve kontrol:** WebSocket.
- **Karar mantığı telefonda:** Tespit ve karar mantığının tamamı telefonda
  çalışır; gözlük yalnızca kamera/ses/sensör kaynağıdır.
- **`frm` (taslak):** Tek kare çekme komutu değil, **akışı başlat/durdur**
  komutudur. `{"t":"frm","on":true}` SoftAP'ı ve akışı açar, `on:false`
  kapatır. SoftAP bilgisinin (SSID/parola veya sabit adres) BLE üzerinden mi
  yoksa sabit mi paylaşılacağı açık.
- **Telefon tarafı risk:** Android, internetsiz bir Wi-Fi'ye bağlanırken
  mobil veriyi bırakabilir; Routes/Places gibi internet isteyen çağrılar bu
  yüzden kırılabilir. Uygulamaya özel ağ bağlama (`WifiNetworkSpecifier`)
  ile akış SoftAP'tan, diğer istekler mobil veriden gitmelidir. Cihazda
  doğrulanacak (bkz. CLAUDE.md "Bekleyen telefon testleri").
