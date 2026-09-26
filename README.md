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
flutter run                     # varsayılan: simülasyon modu
flutter test                    # birim + widget testleri
flutter analyze
```

Özellik bayrakları ve (ileride) API anahtarları koda gömülmez:

```bash
cp dart_defines.example.json dart_defines.json   # git'e girmez
flutter run --dart-define-from-file=dart_defines.json
```

Kısa sesleri yeniden üretmek için: `dart run tool/generate_earcons.dart`

## Sesli komutlar

Test Modu'ndaki **Sesli Komut Ver** butonu telefonun mikrofonunu kullanır.
Gözlük gerekmez.

| Niyet | Örnek | Durum |
|---|---|---|
| ARA | "Ahmet'i ara", "ara Emre" | Arama ekranını numarayla açar |
| MESAJ | "Ayşe'ye mesaj gönder" | SMS ekranını açar |
| NAVİGASYON | "Kadıköy iskelesine götür" | Google Maps yürüyüş yönlendirmesi |
| SAAT | "Saat kaç" | ✅ |
| AYAR | "Daha hızlı konuş", "kısa anlat", "titreşimi azalt" | ✅ |
| HAVA / HABER / MÜZİK / OKU / GEÇİŞ MODU | "Hava durumu nasıl" … | Henüz hazır değil (Faz 5, 8) |

## Dokümanlar

- [Mimari](docs/architecture.md): modüller ve akış
- [BLE protokolü](docs/ble_protocol.md): gözlük ↔ telefon mesajları (firmware ekibi için)
- [TODO.md](TODO.md): ertelenen kararlar ve açık işler
