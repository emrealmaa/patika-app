# BiGG demo hazırlığı: temiz ekran kaydı

Amaç: gerçek gözlük yokken Test Modu ve simülasyonla, kişisel veri ve gizli
anahtar göstermeden kısa bir ekran kaydı almak. Bu belge **yalnızca anlatım**dır;
yeni özellik eklemez. Bu akışın hiçbir adımı telefonda denenmedi (bkz.
[phone_test_checklist.md](phone_test_checklist.md)); ilk çekimden önce bir kez
prova yapılmalı. Simülasyon, gerçek gözlüğün davranışını **göstermez**:
kayıtta "simülasyon" olduğu söylenmeli (gerçek gözlük, MJPEG akışı ve
firmware henüz yok).

## 1. Hazırlık

1. **Derleme:** `flutter run --flavor direct` (debug; simülasyon açık
   başlar). `dart_defines.json` **verme** (anahtarsız): Google anahtarı ve SOS
   test numarası derlemeye girmez, kayıtta sızma riski kalmaz. Navigasyon
   bölümü anahtarsızken Haritalar yedeğine düşer, o kısım için Test Modu'nun
   deneme rotası kullanılır (aşağıda).
2. **Temiz profil:** Uygulama verisini sil (Ayarlar > Uygulamalar > Patika >
   Depolama > Verileri sil) ya da yeni kullanıcı profili aç; gerçek takma ad,
   acil kişi ve komut geçmişi kalmasın. Telefon rehberinde yalnızca uydurma
   kişiler bulunsun (ör. "Deneme Kişi").
3. **Test Modu'nu aç:** Ayarlar > sürüm satırına 7 dokunuş. Alt çubukta Test Modu
   sekmesi çıkar. Simülasyon anahtarı ("Simülasyon modu") orada, açık olmalı.
   Test Modu sekmesi **kayda girmeyecekse** gizle; sesli duyuruları kaydetmek
   için ses kaydı açık olsun.
4. **Bildirimler:** Rahatsız Etmeyin aç, kayıtta bildirim gölgesi çıkmasın
   (gerçek mesaj önizlemeleri sızar). Kalıcı "Patika gözlüğe bağlı" bildirimi
   zararsızdır.
5. **Sesli duyuruların kaydı:** Ekran kaydında telefonun iç sesi kaydedilsin
   (Android ekran kaydı > "Medya sesi"); mikrofon sesi kapalı olsun, yoksa
   konuşmalar ve ortam sesi karışır.
6. **SOS için:** acil kişi olarak yalnızca uydurma/kendi ikinci numaranı ekle
   ve geri sayımı **mutlaka iptal et** (aşağıda). `direct` türünde geri sayım
   bitince SMS gerçekten gider. Hiç risk almak istemiyorsan `--flavor play`
   ile çek: geri sayım başlamaz, "Bu sürümde acil durum mesajı gönderilemiyor"
   duyulur, SOS iptal sahnesi çekilemez.

## 2. Simülasyonda hazır olan senaryolar

Hepsi Test Modu sekmesinden tetiklenir (ya da elle komut göndererek).

| Senaryo | Nasıl tetiklenir | Ne görülür/duyulur |
|---|---|---|
| **Engel uyarısı** | Test Modu > "Engel titreşimi simülasyonu" aç, "Engel mesafesi" kaydırıcısını azalt | Telefon titreşimi (ritim mesafeyle sıklaşır). **Not:** gerçek ürün kararı engel uyarısını gözlükte yerel earcon olarak veriyor; buradaki yalnızca telefon taklidi, "gözlük uyarısı" diye sunulmamalı |
| **Kavşak (karşıya geçiş)** | "Deneme rotasını başlat", ardından "Rotada 50 metre yürü" birkaç kez (rota: 200 m kuzey, 150 m doğu, 20 m geçiş, 100 m kuzey). Geçiş noktasına gelince navigasyon susar | Dönüş/geçiş duyuruları (50/15 m), geçiş duraklaması; çıkış: "Geçtim (duraklamayı bitir)" ya da gözlük "Çift dokunuş" (ilk 3 sn korumalı) |
| **Navigasyon** | Aynı deneme rotası; "Rotadan sap (40 metre)", "Rotaya dön", "Konumu zayıflat" | Rota dışı ve "konum belirsiz" duyuruları; "Navigasyon durumu" satırı |
| **Bağlantı kopma** | Gözlük simülasyonu bölümünde "Gözlük menzil dışında" ya da "Gözlük donmuş gibi davransın" aç | Bağlantı sekmesinde "bağlı değil", sesli "koptu" (`high` öncelik), yeniden bağlanma denemeleri; kapatınca geri gelir |
| **Pil uyarısı** | "Telefon pil seviyesi" kaydırıcısını 30 / 15 / 5'in altına çek; "Gözlük pil seviyesi" kaydırıcısı 20 / 10 / 5. "şarjda" anahtarı uyarıyı susturur | Eşik başına bir kez sesli uyarı; %5'te titreşim hatırlatması. Konuş sekmesinde pil kartları |
| **SOS geri sayımı ve iptali** | Gözlük simülasyonu > "Uzun bas" (acil kişi ekli olmalı) | 7 sn sesli geri sayım + bip; **iptal:** ekrandaki İptal düğmesi, gözlük "Dokun", ya da sesle "iptal". "Dur" iptal etmez. Çekimde 2-3. saniyede iptal et |
| **Gelen arama** | "Gelen arama simülasyonu": arayan adı yaz (varsayılan uydurma "Ahmet Yılmaz"), başlat | Arayan adı okunur; "Dokun" açar, "Uzun bas" reddeder |
| **Gözlük butonları** | "Dokun", "Çift dokunuş", "Uzun bas", "Çift baş sallama" | Dinleme başlar vb.; son olay satırı görünür |
| **Sesli komut** | Konuş düğmesi: "saat kaç", "durum", "Deneme Kişi'yi ara" | Sesli sonuç; "Son duyulan" satırı |

## 3. Önerilen kayıt akışı (yaklaşık 2-3 dk)

1. Konuş ekranı (boş durum) → düğmeye dokun, "durum" de.
2. Test Modu: gözlük bağlı → "Gözlük menzil dışında" → Bağlantı sekmesi → geri aç.
3. Telefon pili kaydırıcısı → 30'un altı: sesli uyarı.
4. Deneme rotasını başlat → yürü → rotadan sap → kavşakta duraklama → "Geçtim".
5. Gelen arama simülasyonu.
6. Gözlük "Uzun bas" → SOS geri sayımı → sesle ya da ekrandan **iptal**.
7. Kapanış: Ayarlar ekranı (kişi bilgisi içermeyen bölümler).

## 4. Kayıtta GÖSTERİLMEMESİ gerekenler

- **Gerçek isim ve numara:** rehber, takma adlar, acil kişiler, "Son duyulan" ve
  Bağlantı > "Son komutlar" satırları gerçek isimleri tutar; kayıttan önce
  temizle ya da yalnızca uydurma kişiler kullan. Gelen mesaj bildirimleri
  (okunan mesajlar) ve SMS ekranı da kayıt dışı kalmalı.
- **API anahtarı:** `dart_defines.json`, terminal çıktısı, `--dart-define` içeren
  komut satırı, Cloud Console ekranı. Anahtarsız derleme bunu kökten çözer.
- **Cihaz kimliği (MAC/UUID):** release'te Bağlantı sekmesi göstermez; debug'da
  bile cihaz kartı yalnızca ad gösterir, ama terminal/log çıktısı (`flutter run`
  konsolu, adb logcat) cihaz kimliği ve kişi adı içerebilir: **konsolu kayda
  alma**.
- **SOS test numarası** (`PATIKA_SOS_TEST_NUMBER`) ve gerçek acil kişi numaraları.
- **Test Modu sekmesinin ham günlüğü** ve teknik ifadeler (niyet
  adları): izleyiciyi yanıltır ve gerçek komut geçmişini sızdırabilir.
- Gizli Test Modu açma jesti (7 dokunuş) kayda girerse sorun değil, ama
  gerçek kullanıcı arayüzü olarak sunulmamalı.

## 5. Çekilebilir ekran görüntüleri

| Ekran | Hangi durumda |
|---|---|
| Konuş | Boş durum; dinleme (nabız halkaları); sonuç ("Son duyulan") |
| Konuş (pil kartları) | Gözlük bağlı + gözlük pili; telefon şarjda; pil düşük |
| Bağlantı | "Gözlük bağlı"; aranıyor; bağlı değil; bulunan cihaz kartı (yalnızca ad) |
| Ayarlar | Konuşma/titreşim ayarları; "Mesaj uygulaması"; "Mesajları okunan uygulamalar"; "SOS nasıl çalışır?" açık |
| SOS tam ekranı | Geri sayım sürerken (koyu zemin, İptal düğmesi) |
| Test Modu | Yalnızca tanıtım dışı iç kullanım için; kayda/görsele girmesin |

## 6. Simülasyonda eksik, demoda işe yarayacak senaryolar (yalnızca liste; yazılmadı)

- Yerel earcon ile **gözlük engel uyarısı** (donanım/firmware gerekir; şu an yalnızca telefon titreşim taklidi var).
- **Kafa hizası/dal gibi tespit** (Python tarafı `ozel_tespit.py`'nin telefonda çalışması; companion app'te yok).
- Gözlük **kamera akışı** ile uçtan uca görüntü (MJPEG simülasyonu var, sentetik kareler; gerçek gözlük yok).
- Gerçek **Google rota/yer araması** anahtarlı sahne (anahtarsız demoda yok; anahtar gösterilemez, yalnızca sonuç kaydı).
- **Gelen mesaj okuma** için hazır simülasyon (bildirim erişimi gerçek bildirimlerle çalışır; sahte mesaj enjekte eden Test Modu düğmesi yok, `notification` bölümü yalnızca erişim durumunu gösterir).
- Çok adımlı sesli **arama/mesaj diyaloğunun** sessiz tetiklenmesi (Test Modu'nun elle komutu diyalog başlatır ama yanıtlar sesle verilmeli).
- SOS'un **gönderim sonuçları** (SMS "gönderildi" raporu) güvenli taklidi; `play` türünde yalnızca "desteklenmiyor" duyulur.
