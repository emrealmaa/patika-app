# TODO / Kapsam Dışı Bırakılan Kararlar

Bu dosya, ilk iskelet kurulumu sırasında bilinçli olarak ertelenen ya da
varsayımla ilerlenen kararları kaydeder - `patika` reposundaki NOTES.md'nin
aynı amaçla kullanılma alışkanlığına uyularak.

## 1. MESAJ niyetinde mesaj METNİ yakalanmıyor (v1 kapsam kararı, kullanıcı onaylı)

`patika` reposundaki `intent_classifier.py`/`gemini_classifier.py` sadece
alıcı ismini (`entity`) çıkarıyor, mesaj gövdesini hiç yakalamıyor. v1'de
`MessageHandler` bu yüzden sadece alıcıyı bulup native SMS uygulamasını
(`sms:` URI) dolduruluş halde açıyor - mesaj metni kullanıcının kendi
girişine bırakılıyor.

**Yapılması gereken (ayrı görev):** çok parçalı sesli komut akışı - gözlük
tarafında "kime" sorusundan sonra "ne yazayım" diye ikinci bir dinleme
turu açıp mesaj içeriğini de `entity`/ayrı bir alan olarak BLE üzerinden
taşımak. Bu hem Python tarafında (intent_classifier akışı) hem BLE mesaj
formatında (bkz. `real_ble_service.dart` JSON şeması) değişiklik gerektirir.

## 2. HAVA / OKU / GECIS_MODU niyetleri sadece placeholder

Bu üçü Python tarafında "telefon eylemi" değil, ayrı birer alt-sistem:

- `HAVA` → `hava_durumu.py` (wttr.in API çağrısı + IP geolocation)
- `OKU` → kamera + easyocr (gerçek bir görüntü işleme özelliği)
- `GECIS_MODU` → `crossing_mode.py` (trafik ışığı + araç izleme durum makinesi)

Bu görevin kapsamı "gözlükten gelen komutları telefon eylemine yönlendirme"
(BLE + call/sms/navigasyon/müzik/haber gibi native telefon işlevleri) idi -
bu üç niyet `command_router.dart` üzerinden tanınıyor ve çökmeden
bilgilendirici bir sonuç dönüyor (`weather_handler.dart`, `ocr_handler.dart`,
`crossing_mode_handler.dart`), ama gerçek mantık henüz yok.

**Yapılması gereken (ayrı, bağımsız görevler):**
- HAVA: wttr.in çağrısını Dart'a taşımak (basit, tek bir görev).
- OKU: kamera + OCR paketi (örn. `google_mlkit_text_recognition`) entegrasyonu.
- GECIS_MODU: `crossing_mode.py`'nin çok daha büyük görü-tabanlı durum
  makinesinin Dart karşılığı - muhtemelen ayrı bir plan/onay gerektirir.

## 3. MÜZİK/HABER niyetleri sadece placeholder (2026-09-22'de kullanıcı kararıyla ertelendi)

İlk sürümde Spotify/Google Haberler'e varsayımla bağlanan gerçek handler'lar
yazılmıştı, ama kullanıcı bunun öncelik dışı olduğunu, ana hatlar
(BLE + ARA/MESAJ/NAVİGASYON) tamamlanmadan bu detayla uğraşılmaması
gerektiğini belirtti. `music_handler.dart`/`news_handler.dart` artık
`weather_handler.dart` ile aynı desende sade birer placeholder - niyeti
tanıyor, çökmüyor, ama hiçbir uygulama açmıyor.

**Yapılması gereken (ayrı görev, düşük öncelik):** hangi müzik
servisi/haber kaynağının kullanılacağı kullanıcıyla netleştirilip gerçek
`url_launcher` entegrasyonu (önceki taslak: Spotify `spotify:` URI'si,
Google Haberler `news.google.com`) geri getirilebilir.

## 4. RealBleService'teki UUID'ler placeholder

`lib/ble/real_ble_service.dart` içindeki servis/karakteristik UUID'leri
(`0000ff10.../0000ff11...`) rastgele placeholder değerlerdir - gerçek
ESP32-S3 firmware'i yazıldığında bu iki sabit güncellenmeli. Beklenen
mesaj formatı (`{"intent": "ARA", "entity": "Emre"}`) Python'daki
`siniflandir()` çıktısıyla aynı sözlüğü paylaşacak şekilde tasarlandı.

## 5. BLE kütüphanesi: flutter_blue_plus → flutter_reactive_ble (ÇÖZÜLDÜ, 2026-09-22)

İlk taslakta `flutter_blue_plus` kullanılmıştı. Paketin LICENSE.md'si
incelendiğinde şu netleşti: Section 2 (ücretsiz "Open Use") sadece
*"registered nonprofit organization, accredited educational institution, or
personal user"* için geçerli - şirket büyüklüğü (çalışan sayısı) bunu
etkilemiyor, sadece HANGİ ücretli tier'a (Starter/Team/Business/...)
girildiğini belirliyor. Ayrıca Section 3.3 açıkça *"development, testing, or
evaluation by a for-profit organization is considered commercial use"*
diyor - yani for-profit bir şirket için geliştirme/test aşamasında bile
ücretsiz kullanım yok. Patika (`patika/NOTES.md`'deki TÜBİTAK 1512/BiGG
başvurusu ve hedef satış fiyatı göz önüne alınınca) for-profit bir girişime
benziyor, bu yüzden `License.nonprofit` kullanmak lisans ihlali riski
taşıyordu.

**Çözüm:** `RealBleService`, arayüzü (`PatikaBleService`) değişmeden,
`flutter_reactive_ble` (BSD-3-Clause - şirket büyüklüğünden/kâr amacından
bağımsız, tamamen ücretsiz, hiçbir ödeme tier'ı yok) kullanacak şekilde
yeniden yazıldı. `SimulatedBleService` ve `CommandRouter`'a dokunulmadı -
her ikisi de zaten `PatikaBleService` arayüzü üzerinden çalışıyordu.
Bağlantı modeli farklı: `flutter_reactive_ble`'de bağlantı,
`connectToDevice()`'ın döndürdüğü stream'i DİNLEMEKLE kurulur, stream
subscription'ını İPTAL ETMEKLE kesilir (ayrı bir `disconnect()` API'si
yok) - `real_ble_service.dart`'taki `disconnect()` metodu bunu yapıyor.
`flutter analyze` temiz, mevcut 8 test değişmeden geçiyor.

**Ek düzeltme (aynı geçişte fark edildi):** `permission_handler` paketi
`pubspec.yaml`'da vardı ama hiçbir yerde kullanılmıyordu - Android 12+'ta
`BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`'i manifest'te tanımlamak yetmiyor,
çalışma zamanında da kullanıcıdan izin istenmesi gerekiyor (yoksa tarama
sessizce başarısız olur/istisna fırlatır). `RealBleService.startScan()`
ve `.connect()` artık taramadan/bağlanmadan önce `_ensurePermissions()`
ile bu izinleri (+ API 30 ve altı için konum izni) istiyor.

## 6. Kişi çözümlemesinde belirsizlik

`contact_resolver.dart`, aynı isimde birden fazla kişi olduğunda ilk
eşleşeni döner - hangisinin kastedildiğini ayırt etme (örn. "hangi Emre?"
diye sesli sormak) kapsam dışı bırakıldı.

---

# Yapılacaklar (belge senkronizasyonu, 2026-09-22)

Aşağıdaki maddeler, platform kararının Flutter'a kesinleşmesi ve
`MIMARI.md`'deki "Saha Riskleri" bölümünün yazılması sırasında tespit
edilen, henüz kod olarak karşılığı olmayan işler. Öncelik + ilgili
ilke/risk referansıyla.

## Uygulama (patika_app)

1. **Bağlantı durumu sesli bildirimi** — gözlük bağlantısı koptuğunda
   "gözlük bağlantısı koptu", geri geldiğinde "gözlük bağlandı" sesli
   olarak bildirilmeli. Sessiz kopma yasak. (İlke 3) — **YÜKSEK**
2. **"Pil azaldı" sesli bildirimi (2026-09-22'de eklendi)** — telefon
   ve/veya gözlük pili azaldığında sesli uyarı verilmeli. **Gerekçe:**
   görme engelli kullanıcı ekrana bakıp pil seviyesini kontrol edemez -
   sesli uyarı olmadan cihaz kapanmadan önce hiç haber alamayıp aniden
   sistemsiz kalabilir, bu da (özellikle kavşak geçişi gibi kritik bir
   anda) güvenlik riski taşır (İlke 3 - zarif bozulma: sessizlik "tehlike
   yok" ile "cihaz öldü" arasında belirsiz kalmamalı). **Önerilen
   davranış:** pil belirli eşiklerin (örn. %20, %10, %5) altına
   düştüğünde BİR KEZ sesli uyarı ver, tekrar tekrar spam yapma (mevcut
   narrator politikasındaki "durum değişmedikçe sessiz kal" ilkesiyle
   aynı desen). Telefon tarafı `battery_plus` gibi bir paketle kolay;
   gözlük tarafı (ESP32-S3 pil seviyesi) BLE üzerinden ayrı bir veri
   alanı gerektirir, henüz tasarlanmadı. (İlke 3) — **YÜKSEK**
3. **Otomatik yeniden bağlanma** — `flutter_reactive_ble` bağlantı
   stream'i hata verip kapandığında (`onError`/`disconnected`) otomatik
   yeniden bağlanma mantığı yok, şu an sadece UI'da "Bağlı değil"
   durumuna düşüyor. (İlke 3) — **YÜKSEK**
4. **Android BLE izin ayrıntıları** — Android 11 ve altı için BLE
   taramasında konum izni; Android 12+ için `BLUETOOTH_SCAN` iznine
   `neverForLocation` bayrağı. (Not: manifest ve `_ensurePermissions()`
   zaten bunu büyük ölçüde kapsıyor - bkz. madde 5 (üstteki "Kapsam Dışı
   Bırakılan Kararlar" bölümü) - gerçek cihazda hiç doğrulanmadı.) —
   **ORTA**
5. **iOS arka plan desteği** — `Info.plist`'e
   `NSBluetoothAlwaysUsageDescription` zaten var, ama
   `bluetooth-central` arka plan modu ve CoreBluetooth state restoration
   henüz yok (bkz. MIMARI.md "Platform Riskleri" madde 1). — **YÜKSEK**
6. **Android foreground service** — ekranı kapalıyken/cepteyken saatlerce
   çalışma için kalıcı bildirimli foreground service + pil optimizasyonu
   muafiyeti isteme akışı henüz yok. — **YÜKSEK**
7. **WiFi görüntü kanalı arayüzü** — BLE yalnızca kontrol/ToF/buton
   verisi içindir; kamera kareleri ayrı bir WiFi (UDP, eski kareyi at)
   kanalından gelecek. Bu kanalın Dart tarafındaki arayüzü henüz
   tasarlanmadı. — **ORTA**
8. **flutter_reactive_ble bakım durumu kontrolü** — son commit tarihi ve
   açık kritik issue'lar gözden geçirilmeli. Lisans serbest olsa da
   bakımı durmuş bir kütüphane de risktir. — **DÜŞÜK**

## Test

9. **Donanımsız gerçek BLE testi** — nRF Connect ile ikinci bir telefonu
   gözlüğün servis/karakteristik UUID'leriyle (bkz. madde 4 - üstteki
   "Kapsam Dışı Bırakılan Kararlar" bölümü) sahte peripheral yapıp
   `RealBleService`'i gerçek BLE yığınına karşı test etmek (şu ana kadar
   sadece `flutter analyze`/`flutter test` ile doğrulandı, gerçek bir
   BLE cihazına hiç bağlanılmadı). — **YÜKSEK**
10. ESP32-S3 kartı gelince gözlüğün UUID'leriyle BLE peripheral olarak
    programlayıp `RealBleService`'i gerçek cihaz ve gerçek kopmalarla
    test etmek.
11. **Geliştirme ortamı** — Android SDK 36 kurulumu (SDK Manager). iOS
    derlemesi için Mac erişimi gerekiyor — nasıl sağlanacağı açık
    problem (bu makine Windows, iOS derlenemiyor).
12. iOS arka plan davranışı gerçek iPhone'da test edilecek (madde 5'in
    parçası).

## Saha / donanım (sensörler gelince)

13. İlk test: VL53L5CX ile öğlen güneşinde farklı kalınlıkta dal ve
    tabela, farklı mesafelerden ölçüm; güvenilir menzil tablosu
    çıkarılacak. (MIMARI.md R5, R7)
14. Dernekte baş eğimi ölçümü, baston ve rehber köpek kullanıcıları
    ayrı ölçülmeli. (MIMARI.md R10)
15. Prototipte multimetreyle gerçek akım ölçümü → güç bütçesi tablosu.
    (MIMARI.md R13)
