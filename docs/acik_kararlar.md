# Açık kararlar

Bu belge **karar vermez**; her açık konuda seçenekleri, koddaki mevcut
varsayılanı, bir öneriyi ve kararın dayanacağı veri/kişiyi netleştirir.
Öneri bağlayıcı değildir. Kaynaklar: `CLAUDE.md`, `docs/barge_in_tasarim.md`,
`docs/ble_protocol.md`, `patika/MIMARI.md`, `patika/NOTES.md`.

| # | Konu | Durum |
|---|---|---|
| 1 | Karşıya geçiş zaman aşımı varsayılanı | Açık, saha verisi bekliyor |
| 2 | Çift dokunuş koruma süresi | Karar verildi (3 sn), saha doğrulaması bekliyor |
| 3 | "dur" istisnası (tam önde çarpışma) | Açık (Python deposu) |
| 4 | Gözlükte engel uyarı kanalı | Açık, firmware bekliyor |
| 5 | OkHttp (gözlük WebSocket) | Ertelendi, firmware bekliyor |
| 6 | Barge-in / Vosk | Ertelendi (Vosk eklenmeyecek kararı var) |
| 7 | Play'de SOS "desteklenmiyor" | Karar verildi (Seçenek 2), Play başvurusu açık |

---

## 1. Karşıya geçiş zaman aşımı varsayılanı

**Sorun:** Kullanıcı kırmızı ışıkta beklerken duraklama üst süreye takılırsa
navigasyon kullanıcı hâlâ kavşaktayken konuşmaya başlar.

**Seçenekler** (üçü de `GuidanceConfig`'te kodlu):
- (a) **Devam et** (`CrossingTimeoutAction.resume`): süre dolunca navigasyon sürer. Süre `crossingMaxPause`.
- (b) **Hatırlatma modu** (`CrossingTimeoutAction.remind`): devam etmez, `crossingMaxReminders` kez bilgi kipinde hatırlatır (`Tr.navCrossingReminder`), sonra devam eder.
- (c) **Işık süresine göre değişken** (`crossingSignalTiming`): yalnızca arayüz var, **veri kaynağı yok**; null dönerse sabit süre.

**Koddaki varsayılan:** (a) `resume`, `crossingMaxPause` = 90 sn.
Bir "hatırlatma modu önerildi" notu var, ama **varsayılan değişmedi** (karar 2026-10-14: saha verisi bekleniyor).

**Öneri:** Sahada 90 sn'nin gerçek kavşaklarda yetmediği görülürse (b) varsayılan olsun
(sessizce devam etmek yerine kullanıcı kavşakta olduğunu duyar); (c) ancak ışık süresi
için güvenilir bir veri kaynağı bulunursa.

**Gereken veri/kişi:** Gerçek kavşaklarda ışık döngü süreleri ve kullanıcıların bekleme
süreleri (yürüyüş denemeleri); O&M uzmanı (Mustafa Özhan Kalaç) ve Altınokta Körler
Derneği kullanıcıları. Hatırlatma cümlesinin anlaşılırlığı.

## 2. Çift dokunuş koruma süresi (karşıya geçiş duraklamasında)

**Sorun:** Duraklamada çift dokunuş navigasyonu devam ettirir; kazara çift dokunuş
(çantaya çarpma) erken devam ettirebilir. Koruma süresince çift dokunuş "son duyuruyu
tekrarla"ya düşer.

**Seçenekler:** koruma yok (`Duration.zero`, eski davranış) · kısa (örn. 1-2 sn) · 3 sn · uzun (5+ sn;
gerçek niyetli çift dokunuşu da geciktirir).

**Koddaki varsayılan:** `crossingDoubleTapGuard` = **3 sn** (kullanıcı kararı 2026-10-14).
Tek dokunuş (dinleme/SOS), uzun basış (SOS), "geçtim" ve konum çıkışı korumadan etkilenmez.

**Öneri:** 3 sn ile başla; sahada "kazara devam" ve "çift dokunuş çalışmıyor sanıldı"
şikâyetlerini say, ona göre ayarla.

**Gereken veri/kişi:** Gerçek yürüyüşte kazara dokunuş sıklığı; kullanıcıların "koruma
varken tekrarla cümlesini" anlaması; gözlük düğmesinin gerçek dokunuş algılama gecikmesi
(donanım).

## 3. "dur" istisnası (tam önde çarpışma riski)

**Sorun:** Proje bilgi kipini benimsiyor (emir yok). Tam önde ve çok yakın bir engelde
"dur" demek bu ilkeyi bozar ama can güvenliği için gerekli olabilir.

**Seçenekler:** (a) deneysel istisna: yalnızca "dur, onunde {nesne} var" kalıbı ·
(b) hiçbir durumda "dur" yok, yalnızca bilgi ("{nesne} çok yaklaştı").

**Koddaki varsayılan:** (a) Python deposunda `narrator.cumle_uret()` bu kalıbı tam önde +
ÇOK YAKIN için üretir; yaklaşan ya da yön değiştiren nesnede kullanılmaz. Karar **açık**
(`patika/CLAUDE.md`, NOTES P0.2.5, MIMARI "Yasaklı kelimeler"). **Bu repoda (patika_app)
navigasyon cümlelerinde "dur" yok**; SOS'ta "dur" iptal etmez.

**Öneri:** Saha testi ve O&M doğrulaması gelene kadar mevcut davranışı koru; sonuç (b)
çıkarsa tek kalıp ve tek test kaldırılır.

**Gereken veri/kişi:** Saha testi + O&M uzmanı (Mustafa Özhan Kalaç) görüşü; gerçek
kullanıcıda "dur"un panik/güven etkisi.

## 4. Gözlükteki engel uyarı kanalı (yerel earcon / telefon)

**Sorun:** Engel uyarısı gecikmeye duyarlı; telefondan geçerse BLE/Wi-Fi gecikmesi ve
bağlantı kopma riski var.

**Seçenekler:** (a) **Gözlükte yerel earcon** (ESP32 flash'ında kısa ses, telefona
sormadan, telefon yalnızca susturabilir) · (b) tüm uyarılar telefondan (BLE ile komut,
telefon ses üretir) · (c) melez: kritik olan yerel, bilgi cümleleri telefondan.

**Koddaki varsayılan:** Mimari karar (a) (`patika/MIMARI.md` "Yerel earcon eşiği",
`docs/ble_protocol.md` §5); **firmware'de doğrulanacak**. Uygulamada yalnızca telefon
titreşim/engel mesafesi simülasyonu var (Test Modu). Zemin/baston menzili engelleri
earcon kapsamı dışında, telefondan sesle.

**Öneri:** (a) ile devam; zon susturma mesajı biçimi ve eşik değerleri firmware ile birlikte
sabitlenmeli.

**Gereken veri/kişi:** Donanım (ESP32-S3, ToF), gerçek gecikme ölçümü (telefon yolu vs yerel),
kulak içi/açık-kulak hoparlörde earcon duyulabilirliği, gürültüde ayırt edilebilirlik
(NOTES/MIMARI: AGC açık Z18); gerçek kullanıcı testi.

## 5. OkHttp (gözlük WebSocket ses/kontrol)

**Sorun:** Dart'ın WebSocket istemcisi gözlük Wi-Fi ağını seçemez (uygulamaya özel
`Network`); native istemci gerekir.

**Seçenekler:** (a) OkHttp (yeni bağımlılık, `Network.socketFactory` ile) · (b) native
`HttpURLConnection`/`java.net` ile elle WebSocket (bağımlılıksız ama kırılgan) ·
(c) WebSocket yerine MJPEG gibi düz HTTP ya da UDP · (d) hiç eklememe, kontrolü BLE'de tutma.

**Koddaki varsayılan:** Yazılmadı; `UnimplementedGlassesControlSocket`
(`lib/camera/glasses_control_socket.dart`). Karar (2026-10-14): **firmware gelince OkHttp ile**.

**Öneri:** Firmware ses/kontrol protokolü netleşmeden bağımlılık ekleme. Proje kuralı:
yeni paket onay ister.

**Gereken veri/kişi:** Firmware ekibi/protokol (ses codec'i, çerçeveleme); gerçek gözlükle
gecikme ve kopma ölçümü; paket onayı (kullanıcı).

## 6. Barge-in (sesle araya girme) / Vosk

**Sorun:** Kulaklıkla TTS konuşurken tetikleyicisiz "dur / tekrar et / yardım".

**Seçenekler:** (a) bulut STT ile sürekli dinleme (uygun değil: oturum süreleri, sistem bip,
SCO) · (b) yerel anahtar kelime tanıyıcı (Vosk dışı bir çözüm) · (c) Vosk (**eklenmeyecek**,
kullanıcı kararı 2026-10-14) · (d) hiç yapma; tetikleyici yolu yeterli.

**Koddaki varsayılan:** (d): bugünkü davranış `test/barge_in_lock_test.dart` ile kilitli;
kod yazılmadı. Tasarım: [barge_in_tasarim.md](barge_in_tasarim.md).

**Öneri:** Önkoşullar (yerel tanıyıcı + SCO/yankı/bip/pil cihaz testleri) tamamlanmadan
başlama; SOS algısına (`getMode`) dokunma riski yüzünden özellik varsayılan kapalı ve
SOS'tan yalıtılmış olmalı.

**Gereken veri/kişi:** Vosk dışı yerel tanıyıcı seçeneği (kullanıcı); SCO'nun
`AudioManager.getMode()`'a etkisi (cihaz testi); Z21 (yanlış SOS alarmı) riski.

## 7. Play'de SOS "desteklenmiyor"

**Sorun:** Google Play, `SEND_SMS`/`CALL_PHONE` izinlerini kısıtlar; SOS'un doğrudan
gönderimi `play` türünde yok.

**Seçenekler:** (1) ekran açan yedek (SMS/arama ekranı hazır açılır) · (2) **desteklenmiyor**,
hemen söyle · (3) Play istisna başvurusu · (4) Play'de hiç dağıtmama.

**Koddaki varsayılan:** (2): `play`'de geri sayım başlamaz; uzun basış ve "yardım" sessiz
kalmaz, "Bu sürümde acil durum mesajı gönderilemiyor" der (112/telefonun kendi özelliği de
söylenir). (1) bilerek yapılmadı: mesajın gittiğini doğrulayamayız, yanıltıcı olurdu.
İlk sürüm `direct`; Play istisna başvurusu ilk sürümde açılmaz.

**Bilinen tutarsızlık:** Ayarlar'daki "SOS nasıl çalışır?" kartı `play`'de hâlâ `direct`
davranışını anlatır (sesli eğitim düzeltildi).

**Öneri:** `direct` ile başla; Play yayını gündeme gelirse başvuru ayrı karar, o güne dek
kartı derleme türüne göre ayır (küçük iş, karar gerektirmez ama henüz yapılmadı).

**Gereken veri/kişi:** Play politika incelemesi (güncel izin kısıtı metni), hukuki görüş
(yanıltıcı güvence ve sorumluluk), dernek/kullanıcı dağıtım tercihi (`direct` APK ile
yetinilir mi).
