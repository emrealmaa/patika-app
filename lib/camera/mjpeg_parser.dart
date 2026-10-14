import 'dart:convert';
import 'dart:typed_data';

/// MJPEG (`multipart/x-mixed-replace`) akışını parça parça gelen baytlardan
/// JPEG karelerine ayıran saf mantık. Ağdan bağımsız: native taraf baytları
/// olduğu gibi verir, burada çözülür.
///
/// - Sınır (boundary) biliniyorsa her parça `--sınır` + başlıklar + boş satır
///   + gövdedir. `Content-Length` varsa gövde o kadar bayttır; yoksa gövde
///   JPEG SOI (FF D8) ile EOI (FF D9) arasıdır.
/// - Sınır bilinmiyorsa (başlık gelmedi) yalnızca SOI..EOI taranır.
/// - Bozuk kare (SOI/EOI yok, yanlış uzunluk, [maxFrameBytes]'tan büyük) atılır
///   ve [dropped] artar; ayrıştırıcı bir sonraki sınırda yeniden hizalanır.
///   Bozuk bir paket akışı asla kilitlemez.
class MjpegParser {
  final int maxFrameBytes;
  final List<int> _marker;

  /// Başlık bölümü bundan uzunsa bozuk sayılır.
  static const maxHeaderBytes = 8 * 1024;

  final List<int> _buf = [];
  bool _inBody = false;
  int? _contentLength;

  /// Atılan (bozuk ya da çok büyük) kareler.
  int dropped = 0;

  MjpegParser({String? boundary, this.maxFrameBytes = 512 * 1024})
      : _marker = boundary == null || boundary.isEmpty ? const [] : latin1.encode('--$boundary');

  /// `multipart/x-mixed-replace; boundary=frame` -> `frame`. Sınırın başına
  /// yanlışlıkla yazılmış `--` ve tırnaklar atılır. Bulunamazsa null.
  static String? boundaryFromContentType(String? contentType) {
    if (contentType == null) return null;
    final m = RegExp(r'boundary\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
    var b = m?.group(1)?.trim();
    if (b == null || b.isEmpty) return null;
    while (b!.startsWith('--')) {
      b = b.substring(2);
    }
    return b.isEmpty ? null : b;
  }

  /// Yeni baytları ekler, tamamlanan kareleri döndürür.
  List<Uint8List> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Uint8List>[];
    while (_step(out)) {}
    _guardSize();
    return out;
  }

  bool _step(List<Uint8List> out) => _inBody ? _body(out) : _seek();

  /// Sıradaki parçanın başını (sınır + başlıklar) ya da sınır yoksa SOI'yi bul.
  bool _seek() {
    if (_marker.isEmpty) {
      final soi = _indexOf(_soi, 0);
      if (soi == -1) {
        _keepTail(1);
        return false;
      }
      _buf.removeRange(0, soi);
      _inBody = true;
      _contentLength = null;
      return true;
    }
    final at = _indexOf(_marker, 0);
    if (at == -1) {
      _keepTail(_marker.length - 1);
      return false;
    }
    final headersStart = at + _marker.length;
    final end = _indexOf(_crlf2, headersStart);
    if (end == -1) {
      if (_buf.length - at > maxHeaderBytes) {
        dropped++;
        _buf.removeRange(0, headersStart);
        return true;
      }
      _buf.removeRange(0, at);
      return false;
    }
    _contentLength = _parseLength(latin1.decode(_buf.sublist(headersStart, end), allowInvalid: true));
    _buf.removeRange(0, end + _crlf2.length);
    _inBody = true;
    return true;
  }

  bool _body(List<Uint8List> out) {
    final length = _contentLength;
    if (length != null) {
      if (length <= 0 || length > maxFrameBytes) {
        // Yanlış/çok büyük uzunluk: gövdeyi atlamaya çalışma, sonraki sınırda hizalan.
        dropped++;
        _inBody = false;
        return true;
      }
      if (_buf.length < length) return false;
      final frame = Uint8List.fromList(_buf.sublist(0, length));
      _inBody = false;
      if (_isJpeg(frame)) {
        _buf.removeRange(0, length);
        out.add(frame);
      } else {
        // Uzunluk yalan söylüyor (sınır kayması): baytları atma, sınırı ara.
        dropped++;
      }
      return true;
    }

    final soi = _indexOf(_soi, 0);
    final nextPart = _marker.isEmpty ? -1 : _indexOf(_marker, 0);
    if (nextPart != -1 && (soi == -1 || nextPart < soi)) {
      // Gövdesi olmayan ya da JPEG olmayan parça.
      dropped++;
      _buf.removeRange(0, nextPart);
      _inBody = false;
      return true;
    }
    if (soi == -1) return false;
    final eoi = _indexOf(_eoi, soi + 2);
    final cut = _marker.isEmpty ? -1 : _indexOf(_marker, soi);
    if (cut != -1 && (eoi == -1 || cut < eoi)) {
      // Kare bitmeden yeni parça başladı: yarım kare.
      dropped++;
      _buf.removeRange(0, cut);
      _inBody = false;
      return true;
    }
    if (eoi == -1) {
      if (_buf.length - soi > maxFrameBytes) {
        dropped++;
        _buf.clear();
        _inBody = false;
        return true;
      }
      return false;
    }
    if (eoi + 2 - soi > maxFrameBytes) {
      dropped++;
    } else {
      out.add(Uint8List.fromList(_buf.sublist(soi, eoi + 2)));
    }
    _buf.removeRange(0, eoi + 2);
    _inBody = false;
    return true;
  }

  /// Hiç sınır gelmeden tampon şişmesin.
  void _guardSize() {
    if (_inBody) return;
    final limit = maxFrameBytes + maxHeaderBytes;
    if (_buf.length > limit) {
      dropped++;
      _keepTail(_marker.isEmpty ? 1 : _marker.length - 1);
    }
  }

  void _keepTail(int n) {
    if (_buf.length > n) _buf.removeRange(0, _buf.length - n);
  }

  static int? _parseLength(String headers) {
    for (final line in headers.split('\n')) {
      final i = line.indexOf(':');
      if (i == -1) continue;
      if (line.substring(0, i).trim().toLowerCase() != 'content-length') continue;
      return int.tryParse(line.substring(i + 1).trim());
    }
    return null;
  }

  static bool _isJpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return false;
    var end = b.length;
    while (end > 2 && (b[end - 1] == 0x0A || b[end - 1] == 0x0D)) {
      end--;
    }
    return b[end - 2] == 0xFF && b[end - 1] == 0xD9;
  }

  int _indexOf(List<int> pattern, int from) {
    final n = _buf.length - pattern.length;
    outer:
    for (var i = from; i <= n; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (_buf[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static const _soi = [0xFF, 0xD8];
  static const _eoi = [0xFF, 0xD9];
  static const _crlf2 = [0x0D, 0x0A, 0x0D, 0x0A];
}
