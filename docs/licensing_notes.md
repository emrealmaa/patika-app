# Lisans notu: tespit ve derinlik modelleri

> **Hukuki tavsiye değildir.** Bu not kodu okuyarak ve resmî lisans sayfalarına
> bakarak hazırlandı; karar vermez. Ürünleştirmeden önce bir avukat/lisans
> uzmanıyla doğrulanmalı. Resmî metin kontrolü 2026-10-16'da GitHub'daki
> `LICENSE` dosyalarına bakılarak yapıldı (yalnızca lisans adı/sürümü ve §13
> özeti okundu; tam metin ve Ultralytics'in ticari lisans koşulları
> **doğrulanamadı**).

## 1. Kodda gerçekten ne kullanılıyor?

**patika_app (Flutter, bu depo):** hiçbir tespit/derinlik modeli yok.
`pubspec.yaml`'da ML paketi (ML Kit, TFLite, ONNX, PyTorch) bulunmuyor; Faz 5
(görsel yardım) iptal edildi. Bağımlılıklar: `flutter_reactive_ble`,
`speech_to_text`, `flutter_tts`, `geolocator`, `http`, `permission_handler`,
`flutter_contacts` vb. (lisansları ayrıca derlenmeli; bu not yalnızca
modelleri kapsar).

**patika (Python, ayrı depo):**

| Amaç | Model / çalışma zamanı | Kaynak (kodda) | Lisans (not) |
|---|---|---|---|
| Nesne tespiti + takip | YOLOv8n (`yolov8n.pt`), `ultralytics==8.4.128`, PyTorch | `detector.py`, `config.json` | Ultralytics: **AGPL-3.0** (doğrulandı) |
| Yol segmentasyonu | YOLOv8n-seg (`yolov8n-seg.pt`), ultralytics | `segmenter.py` | AGPL-3.0 |
| COCO dışı engel | YOLO-World (`yolov8s-world.pt`), ultralytics (+ CLIP) | `ozel_tespit.py` | AGPL-3.0 (CLIP metin kodlayıcı için ayrıca bakılmalı: doğrulanamadı) |
| Derinlik | MiDaS_small (`intel-isl/MiDaS:v3_1`, torch.hub) | `depth_estimator.py` | MiDaS deposu **MIT** (doğrulandı); torch.hub'ın çektiği bağımlılıklar (örn. `gen-efficientnet-pytorch`, timm) ve ağırlık dosyası lisansı ayrıca bakılmalı: doğrulanamadı |
| OCR, STT, yüz | easyocr, openai-whisper, face_recognition/dlib | `ocr.py`, `voice_command.py`, `face_tracker.py` | Bu not kapsamı dışında (Katman 2) |

`patika/README.md` zaten "Ultralytics YOLO (AGPL-3.0)" uyarısını içeriyor.

## 2. AGPL-3.0 bu kullanıma uyuyor mu?

AGPL-3.0 kullanımı **yasaklamaz**; kaynak kodu paylaşma yükümlülüğü getirir.
Ultralytics ayrıca ticari ("Enterprise") lisans sunar. Mevcut durum:

- **Araştırma/prototip/BiGG demosu (kaynak zaten açık, dağıtım yok):**
  yükümlülük pratikte tetiklenmez. Depo public ise kaynak zaten erişilebilir
  (gerçek lisans uyumu için tüm bağımlılıklarla birlikte AGPL ile uyumlu
  bir lisans/niyet beyanı gerekebilir; patika_app lisansı **henüz
  belirlenmedi**, README).
- **Ürünleştirme:** aşağıdaki sonuçlar devreye girer.

## 3. Telefonda dağıtılan uygulamada sonuçlar

- Kopyalayıp dağıtmak (APK/IPA, Play Store, `direct` APK) AGPL'in "convey"
  kapsamındadır: alıcıya **ilgili kaynak kodunu** (değiştirilmiş sürüm
  dahil) AGPL-3.0 ile sunmak gerekir. Birleştirilmiş/türev iş sayılan tüm
  uygulama kodu etkilenebilir; sınır hukuki yorum konusudur.
- §13 (ağ etkileşimi): modeli bir sunucuda çalıştırıp kullanıcılara ağdan
  sunmak, değiştirilmiş kaynağı sunma yükümlülüğünü doğurur. Telefonda yerel
  çalıştırma bu maddeyi değil, dağıtım yükümlülüğünü tetikler.
- Mağaza koşulları: Apple App Store koşullarının GPL/AGPL ile
  uyumsuzluğu sık tartışılır; kesin durum bu nottan **doğrulanamadı**,
  hukuki inceleme gerekir. Google Play'de AGPL bileşenli uygulamalar mümkündür,
  yine kaynak sunma yükümlülüğüyle.
- Kapalı kaynak ürün istenirse: Ultralytics ticari lisansı **ya da** AGPL
  dışı modele geçmek gerekir.
- Mimari not: Dart taşımasında YOLO'nun nasıl çalışacağı (TFLite/ONNX
  dönüşümü) AGPL'i değiştirmez; **ağırlıklar ve model mimarisi** de
  Ultralytics lisansı kapsamındadır (ağırlık lisansı için Ultralytics'in
  güncel açıklamasına bakılmalı: doğrulanamadı).

## 4. Alternatifler (yalnızca ad; uygunluk/doğruluk değerlendirilmedi)

Nesne tespiti, Apache-2.0/MIT/BSD gibi izinli lisanslarla bilinenler (her
birinin güncel lisansı kullanmadan önce kontrol edilmeli):
- RT-DETR (Apache-2.0 olarak yayımlanan sürümler; Ultralytics'in paketlediği
  sürüm AGPL altındadır, dikkat), YOLOX (Apache-2.0), YOLOv7 orijinal repo
  (GPL-3.0, izinli değil), SSD/EfficientDet (TensorFlow Model Garden, Apache-2.0),
  MediaPipe Object Detector (Apache-2.0), PP-YOLOE / PaddleDetection (Apache-2.0),
  D-FINE / DEIM (Apache-2.0 olarak bildirilenler).
- Açık kelime dağarcıklı tespit: OWL-ViT / OWLv2 (Apache-2.0), Grounding DINO (Apache-2.0).
- Segmentasyon: DeepLab, SegFormer (NVIDIA lisansı ayrıca bakılmalı), MediaPipe Image Segmenter.
- Derinlik: MiDaS (MIT), Depth Anything V2 Small (Apache-2.0; büyük sürümler farklı lisanslı).
- Telefon çalışma zamanı: TensorFlow Lite / LiteRT (Apache-2.0), ONNX Runtime (MIT), MediaPipe (Apache-2.0).

## 5. Karar için gereken

- Ürünün dağıtım/kaynak açma niyeti (açık kaynak mı, kapalı mı) ve patika_app lisansı.
- Ultralytics ticari lisans bedeli ve koşulları (resmî satış kanalından).
- Avukat görüşü (AGPL türev iş sınırı, App Store).
- Alternatif modellerle kendi veri setinde doğruluk/gecikme karşılaştırması.
