# Patika Companion (patika-app)

[Patika](https://github.com/emrealmaa/patika) akıllı gözlüğünün **telefon uygulaması**. Gözlükle BLE
üzerinden konuşur, ekrana bakmadan sesli komutla çalışır; arama, mesaj, navigasyon, bildirim okuma ve
SOS'u tek elden yönetir. Birincil kullanıcı görme engelli bireylerdir; tasarım ölçütü "göz alıcı" değil,
**ekran görmeden kullanılabilir** olmaktır.

> **Durum:** Android öncelikli. Gerçek gözlük yok; gözlük tarafı BLE simülasyonuyla test ediliyor.
> iOS planlama aşamasında (kod yok). Rakamlar geliştirici ölçümüdür, hakemli çalışma değildir.

## 1. Özellikler ve doğrulama düzeyi

| Özellik | Düzey | Kanıt / eksik |
|---|---|---|
| Arka plan servisi, bağlantı denetçisi, yeniden bağlanma | Cihazda doğrulandı | Galaxy S24 FE (Android 16, One UI 8.5), ekran kilitliyken sesli komut çalıştı |
| Sesli komut (Türkçe), doğal ifade anlama | Birim testi (+ cihazda kısmen) | 38 cümlelik birim testi 19/38 (%50) → 38/38; telefonda yalnızca birkaç ifade denendi. **Kurallar bu cümlelerle geliştirildi, ayrı doğrulama kümesi yok**, genel doğruluk ölçülmedi |
| Arama, mesaj, navigasyon yönlendirmesi | Cihazda doğrulandı | Yerel uygulamalar doğru açılıyor |
| Kişi eşleştirme (ek almış isimler, bulanık eşleşme) | Birim testi | Eşik değerleri gerçek rehberde tam doğrulanmadı |
| Gelen arama duyurusu | Simülasyon cihazda doğrulandı | Gerçek gelen arama ve ses modu tespiti **doğrulanmadı** |
| Bildirim okuma (WhatsApp/SMS) | İzin akışı cihazda doğrulandı | Gerçek mesajla uçtan uca bekliyor |
| Navigasyon (Google Routes/Places) | Birim testi | Gerçek yürüyüş, konum izni akışı, ekran kapalı senaryo bekliyor |
| SOS (geri sayım, SMS + arama) | Birim testi | **İkinci numarayla gerçek gönderim denenmedi** |
| Pil uyarıları | Birim testi | Cihazda gerçek eşik tetiklemesi bekliyor |
| Erişilebilirlik (TalkBack, kontrast, dokunma alanı) | Cihazda kısmen | Uçtan uca TalkBack turu tamamlanmadı |
| Release'te gerçek BLE ile açılış, gizli Test Modu (7 dokunuş) | Birim testi | Telefonda **doğrulanmadı** (TalkBack ile 7 dokunuş, yeniden açılışta hatırlatma) |

## 2. Parametreler

Bunlar tasarım varsayımlarıdır, saha verisiyle kalibre **edilmemiştir** (`Ayarlanabilir` olanlar yapılandırmadadır).

| Parametre | Değer | Gerekçe |
|---|---|---|
| SOS geri sayımı | 7 sn, ilk 2 sn'de "hemen gönder" sayılmaz | İptal penceresi; tekrarlanan "yardım" tanıma hatasına karşı |
| SOS iptal varsayılanı | **Hiçbir şey yapılmazsa gönderilir** | Yanlışlıkla iptal olan gerçek SOS, yanlışlıkla giden SOS'tan daha kötü |
| Tekrar SOS sınırı | 60 sn (iptal/başarısız olan sayılmaz) | Bilinçsiz tekrar basışa karşı |
| Konum bekleme | Geri sayımla paralel, en çok 3 sn sonra konumsuz gider; konum sonradan gelirse tek takip SMS'i | Konum gecikmesi mesajı geciktirmesin |
| Pil eşikleri | Telefon %30/15/5, gözlük %20/10/5; %5'te 5 dk'da bir titreşim | Her eşik bir kez konuşulur (alarm yorgunluğu); histerezis +5 puan |
| Pil yoklama | 30 sn | Olay dinleyici yerine basit ve güvenli |
| Geçiş duraklaması üst süresi | 90 sn (ayarlanabilir) | Kullanıcı "geçtim" demezse navigasyon sonsuza dek susmasın |
| Yön teyidi (GPS hareket yönü) | ≥15 m ve doğruluğun 2 katı yürünmüş, doğruluk <10 m, hız ≥0,7 m/s, rotanın ilk 100 m'si | GPS hatası genelde 5–15 m (tahmini); yanlış yön söylemek susmaktan kötü |

## 3. Cihazda bulunan hatalar (emülatörde görünmeyenler)

| Hata | Kök neden | Sonuç |
|---|---|---|
| Servis ana ekrana dönünce kapanıyordu | `stopWithTask` davranışı | Düzeltildi; ikinci, daha uzun testle yakalandı |
| TalkBack'te butonlar tetiklenemiyordu | Dışarıdan `excludeSemantics` ile etiket sarma | Etiket butonun içine taşındı; tüm butonları tarayan koruma testi eklendi |
| "Dinliyorum" bip'i duyulmuyordu | Sistem sesi kanalı kısıktı | Bip, konuşmayla aynı kanala alındı |
| "saat kaç" tanındı ama metin kayboldu | Motor ara sonuç gönderiyor, uygulama yalnızca kesin sonuç kabul ediyordu | Ara sonuçlar saklanıyor |

Bu tablo, cihaz testinin vazgeçilmez olduğunun kanıtıdır: dört hatanın dördü emülatörde gözlenmedi.

## 4. Tasarım kararları

| Karar | Reddedilen seçenek | Gerekçe |
|---|---|---|
| `flutter_reactive_ble` | `flutter_blue_plus` | Ticari kuruluşlar için ücretli; geliştirme/test de ticari sayılıyor |
| Arayan kimliği için bildirim dinleyici | `CallScreeningService` | Kullanıcının spam koruma rolünü ele geçirmemek |
| Kritik pil navigasyon/SOS'u durdurmaz | Otomatik kapanma | Sistem kendi başına "yardımı kes" kararı vermemeli |
| Acil kişiler yedeğe girmez (`noBackupFilesDir`) | Varsayılan depolama | Bulut yedeğiyle sızma riski |
| Onay cümlesi yalnızca geri alınamaz eylemde | Her komutta teyit | Gereksiz uzatma; arama/mesajda onay zaten soruluyor |
| **Düşme algılama kaldırıldı** | Telefon IMU'suyla düşme tespiti | Cepte/çantada telefon düşmesini kullanıcı düşmesinden güvenilir ayıramıyor; gerçek kullanıcı talebi yok |
| Faz 5 (görsel yardım) ve Faz 8 (hava/haber/müzik) kaldırıldı | Flutter'da yeniden yazım | Görsel analiz Katman 1'in işi; hava Gemini ile soruluyor; haber/müzik ana amaç dışı |

## 5. Derleme türleri

| Tür | SOS ve doğrudan SMS/arama | Dağıtım |
|---|---|---|
| `direct` | Tam çalışır | Doğrudan APK (dernek, test kullanıcısı) |
| `play` | Desteklenmez; "bu sürümde acil durum mesajı gönderilemiyor" der | Play Store (izin kısıtı) |

## 6. Arayüz

Ayrıntılar ve gerekçeler: `docs/UI_ERISILEBILIRLIK.md`.

- **Açık tema**, renk ve ölçüler tek yerde: `PatikaTokens` (`lib/theme/app_theme.dart`). Metin/zemin çiftleri
  **7:1 (WCAG AAA)** kontrastla ölçülür (`test/theme_contrast_test.dart`). Yalnızca SOS ekranı bilerek koyudur.
- **Yazı tipi:** Plus Jakarta Sans, statik TTF olarak uygulamaya gömülü (`assets/fonts/`); OFL lisansı
  `assets/fonts/OFL.txt` ve `lib/theme/font_license.dart` ile uygulamanın lisans listesinde.
- **Ekranlar:** Konuş, Bağlantı, Ayarlar ve SOS tam ekranı. Üst uygulama çubuğu yok; her ekranın kendi başlığı
  var (TalkBack'te ilk odak). TalkBack açıkken Konuş ekranı başlık + tek büyük düğmedir.
- **SOS ekranı:** `BlockSemantics` arkadaki sekmeleri ve alt çubuğu TalkBack'ten düşürür (testle kanıtlı); odak
  iptal düğmesine zorla taşınmaz.
- **Animasyonlar** yalnızca süstür (`ExcludeSemantics`), yalnızca dinleme/tarama sırasında çalışır ve
  "Animasyonları kaldır" açıkken (`MediaQuery.disableAnimationsOf`) durur.
- Bölüm başlıkları büyük harfe çevrilmez: Dart'ın `toUpperCase()`'i Türkçe "i"yi "İ" yerine "I" yapar.
- **Bilinen sorun:** `play` türünde Ayarlar'daki "SOS nasıl çalışır?" kartı `direct` davranışını anlatıyor
  (TODO.md madde 17).

## 7. Çalıştırma

```bash
flutter pub get
flutter run --flavor direct -d <cihaz-id>
flutter analyze && flutter test   # 680 test
```

Navigasyon için Google Routes/Places anahtarı gerekir. **Koda gömme, depoya ekleme.** `dart_defines.example.json`
dosyasını `dart_defines.json` adıyla kopyalayıp doldur, `flutter run --flavor direct --dart-define-from-file=dart_defines.json`
ile ver (`dart_defines.json` `.gitignore`'da, depoya girmez). Google Cloud'da
anahtarı paket adı ve imza SHA-1 ile yalnızca Routes ve Places API'lerine kısıtla, bütçe uyarısı koy.

**Test Modu** geliştirici aracıdır (gözlük, bildirim, arama simülasyonları). Gerçek kullanıcıya gizlidir;
Ayarlar'daki sürüm satırına 7 kez dokunarak açılır, açıkken her açılışta
düşük öncelikli bir duyuruyla "Test modu açık" söylenir (sırada 10 sn'den fazla beklerse atılır). Release derlemesi
gerçek BLE ile açılır; simülasyon anahtarı yalnızca Test Modu'ndadır. **Bunların ikisi de cihazda henüz doğrulanmadı.**

## 8. Geçerlilik tehditleri

| Sınır | Etki |
|---|---|
| Tek cihaz (Galaxy S24 FE) | Başka üretici/Android sürümlerinde arka plan davranışı farklı olabilir |
| Gerçek gözlük, WiFi akışı, gecikme ölçümü yok | Mimari varsayımlar donanımla sınanacak |
| Dil modeli doğruluğu ayrı kümeyle ölçülmedi | %100 sonucu geliştirme kümesine aittir |
| Kullanıcı görüşmesi nitel, tek kaynak | Genelleme yapılamaz |
| iOS arka plan kısıtı ölçülmedi | iOS desteği için kanıt yok |

Belgeler: `CLAUDE.md` (faz durumu, kararlar, bekleyen testler), `docs/architecture.md`, `docs/ble_protocol.md`,
`docs/sos_phone_test_checklist.md` (SOS telefon deneme listesi), `docs/UI_ERISILEBILIRLIK.md` (arayüz ve erişilebilirlik).
Bu uygulama **acil durum servisi değildir**; SOS deneyseldir ve bastonun/kullanıcının kendi değerlendirmesinin yerini almaz.

**Lisans:** henüz belirlenmedi.
