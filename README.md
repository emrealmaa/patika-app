# Patika Companion

Patika akıllı gözlüğünün (ESP32-S3; kamera, ToF, IMU, titreşim, earbud, BLE,
WiFi) Flutter companion uygulaması. Birincil kullanıcı görme engelli
bireyler; uygulama ekrana bakmadan, sesle ve titreşimle kullanılacak şekilde
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

API anahtarları (ileride) koda gömülmez:

```bash
cp dart_defines.example.json dart_defines.json   # git'e girmez
flutter run --dart-define-from-file=dart_defines.json
```

Kısa sesleri yeniden üretmek için: `dart run tool/generate_earcons.dart`

## Dinlemeyi başlatma

Hepsi aynı yere gider; dinlerken tekrar tetiklemek dinlemeyi iptal eder,
süren konuşmayı da hemen susturur.

| Tetikleyici | Davranış |
|---|---|
| **Konuş** sekmesi (ilk sekme) | Büyük buton. TalkBack açıkken ekranın tamamı tek buton |
| Gözlük butonu: tek dokunuş | Dinlemeyi başlatır |
| Gözlük butonu: çift dokunuş | Son söyleneni tekrarlar |
| Gözlük butonu: uzun basış | Acil durum (Faz 7; şimdilik hazır değil der) |
| Çift baş sallama | Ayarlardan açılırsa dinlemeyi başlatır (varsayılan kapalı) |

Dinleme başlarken "Dinliyorum" yerine kısa bir ses çalar (Ayarlar'dan
değiştirilebilir). İlk açılışta kısa bir sesli eğitim çalar.

## Sesli komutlar

| Niyet | Örnek | Durum |
|---|---|---|
| ARA | "Ahmet'i ara", "annemi arar mısın" | Arama ekranını numarayla açar |
| MESAJ | "Ayşe'ye mesaj gönder" | SMS ekranını açar |
| NAVİGASYON | "Kadıköy iskelesine götür" | Google Maps yürüyüş yönlendirmesi |
| SAAT | "Saat kaç" | ✅ |
| NUMARA | "Mehmet'in numarasını söyle" | ✅ Numarayı rakam rakam okur |
| TAKMA AD | "Annemi Fatma Yılmaz olarak kaydet", "takma adları oku", "annem takma adını sil" | ✅ |
| AYAR | "Daha hızlı konuş", "kısa anlat", "titreşimi azalt" | ✅ |
| DUR | "Dur", "sus", "iptal", "vazgeç" | ✅ Konuşmayı keser (her an) |
| TEKRAR | "Tekrar et", "ne dedin" | ✅ Son söyleneni tekrarlar |
| KOMUTLAR | "Ne yapabilirim", "komutlar" | ✅ Komut listesini okur |
| EĞİTİM | "Eğitimi başlat" | ✅ Sesli eğitimi yeniden oynatır |
| SOS | "Yardım", "imdat", "acil durum" | Faz 7 (şimdilik hazır değil der) |
| HAVA / HABER / MÜZİK / OKU / GEÇİŞ MODU | "Hava durumu nasıl" … | Henüz hazır değil (Faz 5, 8) |

"Şunu anladım: …" teyidi yalnızca telefon eylemi başlatan komutlarda (ara,
mesaj gönder, götür) söylenir: yanlış duyulan bir isim yanlış kişiyi
aratmasın. Bilgi, ayar ve kontrol komutları hemen uygulanır. "Yardım" kelimesi acil durum için ayrılmıştır; komut
listesi "ne yapabilirim" ile açılır.

## Dokümanlar

- [Mimari](docs/architecture.md): modüller ve akış
- [BLE protokolü](docs/ble_protocol.md): gözlük ↔ telefon mesajları (firmware ekibi için)
- [TODO.md](TODO.md): ertelenen kararlar ve açık işler
