import 'dart:convert';
import 'dart:typed_data';

/// Simülasyon ve testler için sentetik "JPEG" kareler. Görüntü İÇERMEZ:
/// yalnızca JPEG işaretleri (SOI, bir COM yorum segmenti, EOI) - taşıma ve
/// ayrıştırma katmanı için yeterli, repoya hiçbir gerçek/kişisel görüntü
/// girmez. Kod çözücüye verilirse çözülemez (bu katmanda kod çözme yok).
abstract final class SyntheticFrames {
  /// [seq] yorumda taşınır; [padding] kareyi istenen boyuta büyütür.
  static Uint8List jpeg(int seq, {int padding = 0}) {
    final comment = latin1.encode('patika-sim-$seq') + List.filled(padding, 0x20);
    final len = comment.length + 2;
    return Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xFE, (len >> 8) & 0xFF, len & 0xFF, ...comment, // COM
      0xFF, 0xD9, // EOI
    ]);
  }

  /// Bir MJPEG parçası: sınır satırı + başlıklar + kare + CRLF.
  static List<int> part(Uint8List jpeg, String boundary, {bool withLength = true}) => [
        ...latin1.encode('--$boundary\r\nContent-Type: image/jpeg\r\n'),
        if (withLength) ...latin1.encode('Content-Length: ${jpeg.length}\r\n'),
        ...latin1.encode('\r\n'),
        ...jpeg,
        ...latin1.encode('\r\n'),
      ];
}
