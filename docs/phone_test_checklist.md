# Telefon deneme listesi

Bu listedeki **hiçbir madde cihazda doğrulanmadı**. Her kutu "geçti" ya da
"kaldı" olarak işaretlenir; kalan maddeler `CLAUDE.md` "Bekleyen telefon
testleri" listesine işlenir. Kaynak: CLAUDE.md "Bekleyen telefon testleri",
[sos_phone_test_checklist.md](sos_phone_test_checklist.md) ve Madde 1-9 işleri.
Her madde kodda var olan bir davranışa karşılık gelir.

**APK türleri** (sütunda kısaltma):

| Kısaltma | Derleme | Ne için |
|---|---|---|
| **D-debug** | `flutter run --flavor direct --dart-define-from-file=dart_defines.json` (debug) | Simülasyon açık başlar, Test Modu kolay; **SOS uçtan uca yalnızca bunda** |
| **D-rel** | `flutter build apk --flavor direct --release` | Gerçek kullanıcı davranışı: gerçek BLE, simülasyon gizli |
| **P-rel** | `--flavor play --release` | `play` davranışı (SOS "desteklenmiyor", doğrudan arama/SMS yok) |

> **SOS uçtan uca asla release APK'yla yapılmaz.** Release'te SOS numarası
> sabit 112'dir (`EmergencyNumber`); test numarası yalnızca debug/profile
> derlemede ve `PATIKA_SOS_TEST_NUMBER` verilmişse kullanılır. "112'yi ara"
> ayarı da release'te gerçek 112'yi arar.

**İkinci telefon:** "2T" = gerekir. Sütunlar her tabloda: Adım → Beklenen →
Geçti/Kaldı → APK → 2T.

---

## A. Sessiz, kütüphanede yapılabilir

Konuşma gerektirmeyen; Test Modu'ndaki elle niyet gönderme alanı (niyet seç +
metin kutusu) simülasyon açıkken sessiz tetikleme sağlar.

### A1. Ekran ve ayarlar

| Adım | Beklenen | ☐ Geçti ☐ Kaldı | APK | 2T |
|---|---|---|---|---|
| Alt çubukta Konuş, Bağlantı, Ayarlar görünür (Test Modu yok) | Üç sekme; üst uygulama çubuğu yok, her ekranın kendi başlığı var | ☐ ☐ | D-rel | - |
| Ayarlar'da hız, ton, ayrıntı, titreşim şiddeti, bildirim türünü değiştir | Seçim kalıcı (uygulamayı kapat-aç), değişince söylenir | ☐ ☐ | D-rel | - |
| Ayarlar > "Mesaj uygulaması": SMS / WhatsApp | Seçim kalıcı; ipucu metni görünür | ☐ ☐ | D-rel | - |
| Ayarlar > "Rehberde olmayan arayanın numarasını oku" | Varsayılan **açık**; kapatınca kalıcı | ☐ ☐ | D-rel | - |
| Ayarlar > "Mesajları okunan uygulamalar": SMS, WhatsApp, WhatsApp Business, Telegram, Signal anahtarları | Varsayılan SMS + WhatsApp + WhatsApp Business açık; hepsi kapanınca "mesaj duyuruları kapalı" söylenir | ☐ ☐ | D-rel | - |
| Ayarlar > "SOS nasıl çalışır?" kartı | Geri sayım 7 sn, "dur" iptal etmez, "Patika acil durum servisi değildir" | ☐ ☐ | D-rel / P-rel | - |
| `play`'de aynı kart | **Bilinen sorun:** kart `direct` davranışını anlatır (play'de SOS desteklenmiyor); not al | ☐ ☐ | P-rel | - |
| Ayarlar > Acil durum > "112'yi ara" aç/kapa | Açarken ceza uyarısı söylenir; kapatınca "ilk acil kişi aranacak" | ☐ ☐ | D-debug | - |
| Ayarlar > "Konuşma sesi" | **Yalnızca iOS'ta** gösterilir/etkili (`voiceId`); Android'de listede görünmesi beklenmez, görünüyorsa not al | ☐ ☐ | D-debug | - |

### A2. Gizli Test Modu

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Ayarlar'da sürüm satırına 7 kez dokun (TalkBack kapalı) | Sayaç ilerler, son dokunuşlarda "N dokunuş daha", 7'de "Test modu açıldı. Alt çubuğa dördüncü sekme olarak eklendi" | ☐ ☐ | D-rel | - |
| Uygulamayı tamamen kapat-aç | Açılışta düşük öncelikli "Test modu açık" duyurulur, sekme duruyor | ☐ ☐ | D-rel | - |
| "Test modunu gizle" | "Test modu gizlendi"; sonraki açılışta sessiz | ☐ ☐ | D-rel | - |

### A3. Release'te görünmemesi gerekenler

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| İlk açılış, Test Modu kapalı | Gerçek BLE ile açılır (`defaultSimulated` release'te false): sahte gözlük bağlanmaz | ☐ ☐ | D-rel | - |
| Bağlantı sekmesi | Simülasyon anahtarı yok; bulunan cihaz kartlarında ham MAC/UUID görünmüyor | ☐ ☐ | D-rel | - |
| Test Modu açıkken simülasyon anahtarı | Yalnızca Test Modu sekmesinde ("Simülasyon modu") | ☐ ☐ | D-rel | - |

### A4. İzin ekranları

Her izin ilk gerektiği anda, önce sesli açıklama sonra sistem penceresi.

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Temiz kurulum, ilk açılış | Yalnızca bildirim izni istenir; toplu izin yok | ☐ ☐ | D-rel | - |
| Eğitimin sonu | Konum, telefon durumu + aramayı aç/reddet, pil muafiyeti istenir (sırayla, açıklamalı); reddedince uygulama çökmez, "arama özellikleri kısıtlı" söylenir | ☐ ☐ | D-rel | - |
| `direct`'te pil muafiyeti | Sistem penceresi (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) açılır; izin verince 60 sn içinde söylenir | ☐ ☐ | D-rel | - |
| `play`'de pil muafiyeti | Pil ayar ekranı açılır + sesli yönlendirme; Play'de bu izin kısıtlı olduğu için pencere yok | ☐ ☐ | P-rel | - |
| İzin reddi sonrası Ayarlar'dan geri verme | Özellik geri gelir | ☐ ☐ | D-rel | - |

### A5. Acil kişi kurulumu (ikinci numarayla) ve yedekleme

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Sesle "acil kişi ekle" (Test Modu'nun niyet listesinde ACIL_KISI yok; bu tek adım kısık sesle söylenmeli) | Rehberden çözülür, onay sorulur, eklenir; `direct`'te SMS izni **kurulum sırasında** istenir | ☐ ☐ | D-debug | evet (ikinci numara kişisi) |
| Rıza SMS'i sorusu | Yalnızca `direct`'te sorulur; "evet" derse SMS **yalnız o kişiye** gider | ☐ ☐ | D-debug | evet |
| `play`'de aynı akış | SMS izni ve rıza sorusu hiç gelmez | ☐ ☐ | P-rel | - |
| "acil kişiler kim" | Liste tek adımda okunur | ☐ ☐ | D-debug | - |
| Yedekleme: kişi ekle, ayarları/takma adı değiştir, `adb backup` ya da hesap yedeği al, uygulamayı sil, geri yükle | **Acil kişiler GELMEMELİ**; ayarlar ve takma adlar GELMELİ | ☐ ☐ | D-rel | - |

---

## B. Sesli komut gerektiren

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Konuş düğmesine dokun, "saat kaç" | Saat söylenir; bip dinleme başlangıcını belli eder | ☐ ☐ | D-rel | - |
| "Ayşe'yi ara" | Onay sorusu → `direct`'te doğrudan arama; `play`'de arama ekranı açılır | ☐ ☐ | D-rel / P-rel | evet |
| "Ayşe'ye mesaj gönder" | Mesaj dikte → geri okuma → onay; `direct`'te SMS gider | ☐ ☐ | D-rel | evet |
| "Ayşe'ye WhatsApp'tan mesaj gönder" / "WhatsApp at Ayşe'ye" | Geri okumada "WhatsApp'tan" denir; sohbet **metin dolu açılır**, "gönderildi" denmez, gönder tuşuna sen basarsın; numara 90... biçiminde | ☐ ☐ | D-rel | evet |
| Ayarlar'da varsayılan WhatsApp, "mesaj gönder" | WhatsApp'tan gider; komutta "SMS" demek yok, varsayılan yeterli | ☐ ☐ | D-rel | - |
| "WhatsApp'tan ara" | Normal arama olarak kalır | ☐ ☐ | D-rel | - |
| "mesaj uygulamaları"; "WhatsApp bildirimlerini kapat" / "aç" (STT "vatsap" yazımları) | Liste söylenir; kapatınca o uygulamanın mesajı duyurulmaz; ayar uygulama yeniden açılınca korunur | ☐ ☐ | D-rel | evet (mesaj gönderen) |
| "durum" / "pil ne kadar" | Gözlük + telefon pili + navigasyon özeti | ☐ ☐ | D-rel | - |
| "yardım" | SOS geri sayımı başlar (yalnızca D-debug'da dene, bkz. D3) | ☐ ☐ | D-debug | evet |
| SOS geri sayımı sürerken "dur" | Geri sayım iptal **olmaz** | ☐ ☐ | D-debug | - |

---

## C. Dışarıda, yürüyerek

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| **ANA SENARYO:** ekran kilitli, telefon cepte, "X'e götür" | Navigasyon başlar ve konum duyuruları ekran kilitliyken sürer; `ACCESS_BACKGROUND_LOCATION` yok (varsayım: servis konum türüyle başladığı için "kullanım sırasında" erişim sürer, **doğrulanmadı**) | ☐ ☐ | D-rel + anahtar | - |
| Anahtar yokken / konum yokken "X'e götür" | Haritalar açılır, nedeni söylenir; çökme yok | ☐ ☐ | D-rel (anahtarsız) | - |
| Google Routes/Places gerçek yanıt | Türkçe yer adı bulunur, "hangisi?" sorulur; 403 yok (anahtar kısıtı: paket + debug/release SHA-1) | ☐ ☐ | D-rel + anahtar | - |
| GPS eşikleri: 50/15 m duyuru, rota dışı 20 m, konum belirsiz, varış 20 m | Şehir içi ve açık alanda makul; yanlış "rota dışı" yok | ☐ ☐ | D-rel | - |
| Yön teyidi | Yürümeye başlayınca bir kez; yanlış "rotanın tersi" yok | ☐ ☐ | D-rel | - |
| Kavşak: karşıya geçiş duraklaması | Navigasyon susar; çıkış kanalları: konum ilerlemesi, "geçtim", gözlük çift dokunuşu (ilk 3 sn korumalı), zaman aşımı (varsayılan 90 sn, devam eder) | ☐ ☐ | D-rel | - |
| Pil optimizasyonu | Galaxy S24 FE'de servis saatlerce öldürülmez (muafiyet verildikten sonra) | ☐ ☐ | D-rel | - |
| Yaklaşık konum izni | "Konum belirsiz" der; kullanıcıya anlaşılır | ☐ ☐ | D-rel | - |
| Telefon pil uyarıları (gerçek kullanımda) | %30/15/5 uyarıları; %5'te 5 dk'da bir titreşim rahatsız etmiyor | ☐ ☐ | D-rel | - |
| Gerçek yürüyüşte cümle tarzı | "30 metre sonra rota sağa sapıyor" anlaşılır (kullanıcı testi gerekir, bkz. CLAUDE.md) | ☐ ☐ | D-rel | - |

---

## D. İkinci telefon gerektiren

### D1. Gelen arama (ikinci telefon arar)

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Rehberdeki kişi arar | Ad söylenir; çalma/açık/boşta durumları doğru (`TelephonyCallback`, Android 16) | ☐ ☐ | D-rel | evet |
| Rehberde olmayan numara arar | Varsayılan: numara rakam rakam okunur; ayarı kapatınca "bilinmeyen bir numara arıyor" | ☐ ☐ | D-rel | evet |
| Bildirim erişimi kapalıyken arama | "bir arama geliyor" (ad yok) | ☐ ☐ | D-rel | evet |
| Gözlük butonu (Test Modu simülasyonu) dokunma / uzun basış | Dokunma açar (`acceptRingingCall`), uzun basış reddeder (`endCall`); çalmıyorken uzun basış SOS | ☐ ☐ | D-debug | evet |
| Görüşme sürerken | TTS susar; pil uyarısı bekletilir, görüşme bitince söylenir; gelen mesaj okunmaz | ☐ ☐ | D-rel | evet |
| Ekran kilitli / uygulama arka planda; çift SIM; `play` türü | Algılama çalışır | ☐ ☐ | D-rel / P-rel | evet |
| İzin penceresi TalkBack ile; reddedilince | "Arama özellikleri kısıtlı" | ☐ ☐ | D-rel | - |

### D2. Gelen mesaj bildirimi

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Bildirim erişimi ver, ikinci telefon SMS ve WhatsApp (kişisel, Business varsa) / Telegram / Signal yollar | Açık uygulamaların mesajı gönderen+içerikle okunur; kapatılanın okunmaz ve günlüğe girmez | ☐ ☐ | D-rel | evet |
| İlk kez | Bir kerelik gizlilik uyarısı söylenir | ☐ ☐ | D-rel | evet |
| "mesajlarımı oku", "son bildirimleri oku", "bildirimleri sustur/aç" | Okunmamışlar içerikle; son 20 yalnızca gönderen; susturma yalnız duyuruyu keser | ☐ ☐ | D-rel | evet |

### D3. SOS uçtan uca (YALNIZCA D-debug, asla gerçek 112)

Ayrıntılı adım listesi: [sos_phone_test_checklist.md](sos_phone_test_checklist.md)
(elle SOS, iptal, sesli SOS, 112 ayarı, kişi yok/SMS izni yok, konum, ekran
kilitli, arama sırasında konuşmama). Hazırlık: `dart_defines.json`'da
`PATIKA_SOS_TEST_NUMBER` = ikinci numaranız ("112" yazma, yok sayılır).

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| 7 sn geri sayım, müdahale yok | SMS tüm acil kişilere, sonra **tek** arama (112 kapalıyken ilk kişi); "gönderildi" yalnızca `sent` iken | ☐ ☐ | D-debug | evet |
| Sesli "iptal" / dokunuş / ekran düğmesi | İptal olur; "dur" iptal etmez | ☐ ☐ | D-debug | - |
| Arama başladıktan sonra | Uygulama konuşmaz; arama bitince (tespit edilirse) özet; tespit edilemezse hiç konuşmaz, geçmişe yazar | ☐ ☐ | D-debug | evet |
| Hoparlör, çift SIM, uçak modu, konumsuz gönderim | Not al (CLAUDE.md "gerçek cihazda uçtan uca" a-g) | ☐ ☐ | D-debug | evet |
| Ekran kilitli ve cepteyken | Konum alınır, sesli iptal çalışır | ☐ ☐ | D-debug | evet |
| `play` derlemesi | Geri sayım başlamaz; "Bu sürümde acil durum mesajı gönderilemiyor" der | ☐ ☐ | P-rel | - |

### D4. nRF Connect ile sahte BLE peripheral

UUID'ler `GlassesGattProfile`'da (tek yer); **gerçek firmware UUID'leri henüz
belli değil**, bu test yer tutucu UUID'lerle `RealBleService`'in BLE yığınına
karşı çalıştığını görmek içindir.

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| nRF Connect'te `GlassesGattProfile`'daki servis/karakteristiklerle peripheral kur | Uygulama gerçek BLE taramasında bulur (Test Modu kapalı) | ☐ ☐ | D-rel | evet |
| Bağlan, `hb` (2 sn) gönder | "Bağlı" ve sağlıklı; heartbeat kesilince 6 sn sonra "koptu" duyurulur, yeniden bağlanma dener | ☐ ☐ | D-rel | evet |
| `btn`, `batt`, `wifi` JSON'ları gönder | Buton davranışı, gözlük pili ve eşikler; geçersiz JSON atlanır, çökme yok | ☐ ☐ | D-rel | evet |
| `frm` yazma (22 bayt) | MTU 20'de sığmama davranışını gözle (protokol §7 açık sorusu) | ☐ ☐ | D-rel | evet |

### D5. Hotspot ile SoftAP internet denemesi

İkinci telefonda internetsiz hotspot (mobil veri kapalı) = gözlük SoftAP'ı
yerine. Kod: `GlassesNetwork.kt` (`WifiNetworkSpecifier`).

| Adım | Beklenen | ☐ ☐ | APK | 2T |
|---|---|---|---|---|
| Test Modu > "Gözlük kamerası Wi-Fi bağlantısı": ağ adı/parolayı elle gir, "Gözlük ağına bağlan" | Sesli yönlendirme sistem penceresinden önce biter; onayla; "bağlandı" | ☐ ☐ | D-debug / D-rel (Test Modu açık) | evet |
| Bağlıyken navigasyon (Routes/Places) ve Gemini | Mobil veriden çalışır; varsayılan ağ değişmez (One UI akıllı ağ değiştirici ve "internetsiz Wi-Fi" uyarısı akışı bozmuyor) | ☐ ☐ | D-rel + anahtar | evet |
| Reddet / "ağ bulunamadı" | `userDeclined` / `unavailable` söylenir | ☐ ☐ | D-debug | evet |
| Hotspot'u kapat-aç | Kopunca `lost` (`high` öncelik); açılınca onaysız yeniden bağlanma | ☐ ☐ | D-debug | evet |
| Wi-Fi kapalıyken bağlan | "Wi-Fi kapalı" | ☐ ☐ | D-debug | - |
| Android 13+ yakındaki cihazlar izni; Android 10-12'de ek izin gerekip gerekmediği | Not al | ☐ ☐ | D-debug | - |
| TalkBack'le sistem onay penceresi | Kullanılabiliyor | ☐ ☐ | D-debug | evet |
| Release'te internet | `INTERNET` ana manifestte; direct release ile Routes/Places gerçekten Google'a ulaşır (Haritalar yedeğine düşmez) | ☐ ☐ | D-rel + anahtar | - |

---

## E. Gözlük / firmware gelince (yalnızca başlıklar)

- Gerçek ESP32 MJPEG akışı: gecikme, kare kaybı/bozuk kare, 400 ms tazelik, 10 kare/sn, pil/ısınma, kapanınca "koptu".
- `frm` mesajının MTU 20 baytta sığmaması (22 bayt) ve gerçek `wifi` mesajı.
- WebSocket ses/kontrol (OkHttp, firmware gelince).
- Gerçek BLE UUID'leri ve `RealBleService` ile gerçek kopmalar.
- Yerel earcon engel uyarısı ve zon susturma mesajı.
- Gözlük uzun basış eşiği (3 sn) ve çift dokunuş.
- Gözlük pil eşiklerinin gerçek pil süresiyle yeniden ayarı.
- Barge-in ([barge_in_tasarim.md](barge_in_tasarim.md)): yerel anahtar kelime tanıyıcı + SCO/yankı/bip/pil testleri.
- iOS gerçek iPhone maddeleri: CLAUDE.md "Gerçek iPhone'da bekleyenler".
