import '../action_result.dart';

/// OKU niyeti. Python tarafında kamera + easyocr ile gerçek bir görüntü
/// işleme akışı (ocr.py) - "telefon eylemi" değil, kendi başına bir özellik
/// (kamera erişimi + metin tanıma modeli).
///
/// KAPSAM DIŞI (v1): bu görevin kapsamı BLE + telefon eylemi yönlendirme
/// idi. Kamera+OCR entegrasyonu (örn. google_mlkit_text_recognition ile)
/// ayrı, bağımsız bir iş kalemi (bkz. patika_app/TODO.md). Şimdilik sadece
/// niyeti tanıyıp bilgilendirici bir sonuç döndürüyor, çökmüyor.
class OcrHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail(
        'OKU: henüz uygulanmadı (kamera+OCR entegrasyonu ayrı görev, bkz. TODO.md)');
  }
}
