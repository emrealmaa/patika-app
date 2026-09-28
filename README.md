# Patika Companion

Patika akıllı gözlüğünün (ESP32-S3; kamera, ToF, IMU, earbud, BLE,
Wi-Fi SoftAP; titreşim motoru yok) Flutter companion uygulaması. Birincil kullanıcı görme engelli
bireyler; uygulama ekrana bakmadan, sesle ve telefonun titreşimiyle kullanılacak şekilde
tasarlanıyor. Android öncelikli, iOS şimdilik ertelendi.

Gözlük donanımı henüz yok: her şey **Simülasyon modunda** çalışır ve
**Test Modu** sekmesinden denenebilir.

## Çalıştırma

```bash
flutter pub get
flutter run --flavor play       # mağaza sürümü (varsayılan seçim)
flutter run --flavor direct     # doğrudan arama/SMS (kendi cihazlar)
flutter test                    # birim + widget testleri
flutter analyze
```

İki derleme türü var (Android, `app/build.gradle.kts`):

| Tür | Onaydan sonra | Neden |
|---|---|---|
| `play` | Arama / SMS ekranı açılır, kullanıcı tuşa basar | Google Play `CALL_PHONE`/`SEND_SMS` izinlerini kısıtlıyor; bu türde izinler hiç yok |
| `direct` | Doğrudan arar / gönderir | Kendi cihazlar ya da mağaza dışı dağıtım |

API anahtarları koda gömülmez, derleme sırasında `--dart-define` ile verilir:

```bash
cp dart_defines.example.json dart_defines.json   # git'e girmez; anahtarı buraya yazın
flutter run --flavor play --dart-define-from-file=dart_defines.json
```

| Anahtar | Ne için | Yoksa |
|---|---|---|
| `PATIKA_MAPS_API_KEY` | Sesli navigasyon: Google **Routes API** (yürüyüş rotası) ve **Places API (New)** (yer arama) | Navigasyon Google Haritalar uygulamasını açan yedek akışla çalışır (sesli soru aynı, rota Haritalar'da) |

Google Cloud'da anahtarı **yalnızca bu iki API ile sınırlayın** ve günlük kota
koyun. Anahtar uygulamanın içine gömülür ve APK'dan çıkarılabilir; bu bir
geliştirme/dağıtım aşaması çözümü. Ürün aşamasında doğru çözüm, anahtarı
sunucuda tutan ve isteği ileten küçük bir ara sunucudur. Anahtar istekte
`X-Goog-Api-Key` başlığıyla gider (adrese yazılmaz) ve günlüklere basılmaz.

Kısa sesleri yeniden üretmek için: `dart run tool/generate_earcons.dart`

## Dinlemeyi başlatma

Hepsi aynı yere gider; dinlerken tekrar tetiklemek dinlemeyi iptal eder,
süren konuşmayı da hemen susturur.

| Tetikleyici | Davranış |
|---|---|
| **Konuş** sekmesi (ilk sekme) | Büyük buton. TalkBack açıkken ekranın tamamı tek buton |
| Gözlük butonu: tek dokunuş | Dinlemeyi başlatır |
| Gözlük butonu: çift dokunuş | Son söyleneni tekrarlar (karşıya geçiş duraklamasındayken navigasyonu devam ettirir) |
| Gözlük butonu: uzun basış | Acil durum (SOS): 7 sn geri sayım, iptal edilmezse acil kişilere SMS + tek arama. Yalnızca `direct` derlemesinde; `play`'de "gönderilemiyor" der |
| Çift baş sallama | Ayarlardan açılırsa dinlemeyi başlatır (varsayılan kapalı) |

Dinleme başlarken "Dinliyorum" yerine kısa bir ses çalar (Ayarlar'dan
değiştirilebilir). İlk açılışta kısa bir sesli eğitim çalar.

## Sesli komutlar

| Niyet | Örnek | Durum |
|---|---|---|
| ARA | "Ahmet'i ara", "annemi arar mısın" | Arama ekranını numarayla açar |
| MESAJ | "Ayşe'ye mesaj gönder" | SMS ekranını açar |
| NAVİGASYON | "Kadıköy iskelesine götür" | Yer sorulur/seçilir, rota özetlenip onay alınır ("… 1,2 kilometre, yaklaşık 15 dakika. Başlayayım mı?"), sonra uygulama içi sesli yönlendirme. Anahtar ya da konum yoksa Google Haritalar açılır |
| NAVİGASYON KONTROLÜ | "Ne kadar kaldı", "navigasyonu bitir", "geçtim" | ✅ Kalan yol/süre; kapat; karşıya geçiş duraklamasını bitir |
| SAAT | "Saat kaç" | ✅ |
| NUMARA | "Mehmet'in numarasını söyle" | ✅ Numarayı rakam rakam okur |
| TAKMA AD | "Annemi Fatma Yılmaz olarak kaydet", "takma adları oku", "annem takma adını sil" | ✅ |
| AYAR | "Daha hızlı konuş", "kısa anlat", "titreşimi azalt" | ✅ |
| DUR | "Dur", "sus", "iptal", "vazgeç" | ✅ Konuşmayı keser (her an) |
| TEKRAR | "Tekrar et", "ne dedin" | ✅ Son söyleneni tekrarlar |
| KOMUTLAR | "Ne yapabilirim", "komutlar" | ✅ Komut listesini okur |
| EĞİTİM | "Eğitimi başlat" | ✅ Sesli eğitimi yeniden oynatır |
| SOS | "Yardım", "imdat", "acil durum" | ✅ Geri sayım; "iptal", "yanlış alarm", "vazgeç", "gerek yok" iptal eder ("dur" iptal etmez) |
| Acil kişi | "acil kişi ekle Ayşe", "acil kişi sil Ayşe", "acil kişiler kim" | ✅ En çok 3 kişi; ekleme onaylı, `direct`de isteğe bağlı bildirim SMS'i |
| HAVA / HABER / MÜZİK / GEÇİŞ MODU | "Hava durumu nasıl" … | Henüz hazır değil (sonraki fazlar) |
| OKU | … | Henüz hazır değil. Faz 5 (görsel yardım) iptal edildi: görsel analiz gözlük+telefon sisteminin işi (bkz. CLAUDE.md) |

Telefon eylemi başlatan komutlar (ara, mesaj gönder, götür) çok adımlı
diyaloğa gider ve eylemden önce onay sorar ("Ahmet Yılmaz'ı arayayım mı?"):
yanlış duyulan bir isim ya da yer yanlış eyleme yol açmasın. Bilgi, ayar ve
kontrol komutları hemen uygulanır. "Yardım" kelimesi acil durum için
ayrılmıştır; komut listesi "ne yapabilirim" ile açılır.

Navigasyon cümleleri yalnızca bilgi verir, emir vermez ("30 metre sonra rota
sağa sapıyor"). Karşıya geçiş noktalarında navigasyon susar; geçiş kararı
navigasyonun değil, Kavşak Geçiş Asistanının işidir.

## Dokümanlar

- [Mimari](docs/architecture.md): modüller ve akış
- [BLE protokolü](docs/ble_protocol.md): gözlük ↔ telefon mesajları (firmware ekibi için)
- [TODO.md](TODO.md): ertelenen kararlar ve açık işler
