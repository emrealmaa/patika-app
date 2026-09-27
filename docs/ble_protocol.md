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
| `hap` | `id` (desen no), `s` (şiddet %0–100) | Titreşim desenini çal | `{"t":"hap","id":9,"s":70}` |
| `frm` | — | *(Ayrılmış)* Tek kare çek ve WiFi ile gönder | `{"t":"frm"}` |

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

## 4. Titreşim desenleri (`hap.id`)

Desenler şiddetle değil **ritimle** ayrışır; en hafif şiddette de ayırt
edilebilmelidirler. Süreler milisaniye: `[bekle, titret, bekle, titret, …]`.
Kaynak: `lib/accessibility/haptic_patterns.dart`.

| id | Ad | Zamanlama (ms) | Anlam |
|---|---|---|---|
| 1 | connected | 0, 60, 80, 140 (yükselen) | Bağlandı |
| 2 | disconnected | 0, 220, 100, 220 (alçalan) | Bağlantı koptu |
| 3 | batteryLow | 0, 150, 200, 150, 200, 150 | Pil düşük |
| 4 | listening | 0, 40 | Dinliyorum |
| 5 | understood | 0, 40, 70, 40 | Anlaşıldı / başarılı |
| 6 | notUnderstood | 0, 350 | Anlaşılamadı |
| 7 | error | 0, 80, 50, 80, 50, 80 | Hata |
| 8 | obstacle | 0, 60 (tekrarlı) | Engel (bkz. §5) |
| 9 | turnLeft | 0, 300, 120, 80 (uzun-kısa) | Sola dön |
| 10 | turnRight | 0, 80, 120, 300 (kısa-uzun) | Sağa dön |
| 11 | incomingCall | 0, 120, 100, 120, 400, 120, 100, 120 (çift-çift) | Gelen arama (Faz 4b) |

Gözlükte iki motor varsa `turnLeft` sol, `turnRight` sağ motorda çalınabilir.
Tek motorda ritim farkı yeterlidir.

## 5. ⚠️ Firmware ekibi için kritik not: engel uyarısı telefondan bağımsızdır

**Engel algılama → titreşim döngüsü gözlüğün içinde, telefondan bağımsız
çalışmalıdır.** BLE koparsa, telefon kapanırsa, uygulama çökerse veya
telefonun pili biterse kullanıcı **yine de** engel uyarısı almalıdır.

- ToF sensörü → mesafe → titreşim aralığı hesabı firmware'de yapılır. Telefon
  bu döngünün içinde **olmamalıdır** (BLE gecikmesi ve kopma riski).
- Önerilen eşleme (uygulamadaki simülasyonla aynı, park sensörü mantığı):
  - 2,5 m ve ötesi: titreşim yok
  - 0,4 m ve berisi: 150 ms aralıkla (neredeyse sürekli)
  - Aradaki mesafeler: 150 ms ile 1000 ms arasında doğrusal
- Telefon yalnızca **ek sesli bilgi** verir ("önünde engel var" gibi). Uygulama
  gözlüğe `hap id=8` **göndermez** (`GlassesHaptics.updateObstacle` bilerek
  boş bırakıldı).
- Heartbeat durursa gözlük engel titreşimini **kesmemelidir**.

## 6. Açık konular

- Gerçek UUID'ler (firmware ile birlikte).
- WiFi kare aktarımı (`frm`): SoftAP mi, telefon hotspot'u mu? Eskiden Faz 5
  (görsel yardım) planındaydı; o faz iptal edildi. Kanal Katman 1 görüntü
  işleme için yine gerekli, karar Python→Dart taşımasıyla (`patika/CLAUDE.md`
  Z7) birlikte verilecek.
- Gözlük pil yüzdesinin nasıl hesaplanacağı (voltaj eğrisi) firmware'e ait.
- Protokol sürümü alanı (`"v"`) şimdilik yok. İlk kırıcı değişiklikte
  bağlanınca `{"t":"hello","v":2}` eklenmesi öneriliyor.
