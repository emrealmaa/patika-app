// Kısa sesleri (earcon) assets/earcons/ altına 16-bit mono WAV olarak
// üretir. Sesler lisans derdi olmasın diye dışarıdan alınmıyor, burada
// sentezleniyor. Çalıştırma: dart run tool/generate_earcons.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 22050;

/// (frekans Hz, süre ms) notaları art arda; frekans 0 = sessizlik.
const _earcons = {
  // Yükselen iki nota: "dinliyorum".
  'listen_start': [(660.0, 70), (990.0, 90)],
  // Alçalan iki nota: "dinleme bitti".
  'listen_end': [(990.0, 70), (660.0, 90)],
  // Majör arpej: "başarılı".
  'success': [(784.0, 60), (988.0, 60), (1175.0, 110)],
  // Pes, iki kez: "hata".
  'error': [(220.0, 130), (0.0, 60), (196.0, 170)],
  // Tek yüksek, kısa bip: acil durum geri sayımı (Faz 7). Kısa tutuldu ki
  // aralarında mikrofon iptal komutunu duyabilsin.
  'sos_tick': [(1320.0, 90)],
};

void main() {
  final dir = Directory('assets/earcons')..createSync(recursive: true);
  _earcons.forEach((name, notes) {
    final samples = <int>[];
    for (final (freq, ms) in notes) {
      samples.addAll(_tone(freq, ms));
    }
    File('${dir.path}/$name.wav').writeAsBytesSync(_wav(samples));
    stdout.writeln('$name.wav (${samples.length} örnek)');
  });
}

Iterable<int> _tone(double freq, int ms) sync* {
  final n = _sampleRate * ms ~/ 1000;
  final fade = min(n ~/ 4, _sampleRate * 8 ~/ 1000); // 8 ms yumuşak giriş/çıkış
  for (var i = 0; i < n; i++) {
    if (freq == 0) {
      yield 0;
      continue;
    }
    final envelope = min(1.0, min(i, n - 1 - i) / max(1, fade));
    // Temel + hafif 2. harmonik: kulaklıkta daha net duyulur.
    final t = i / _sampleRate;
    final v = sin(2 * pi * freq * t) * 0.8 + sin(4 * pi * freq * t) * 0.2;
    yield (v * envelope * 0.6 * 32767).round();
  }
}

Uint8List _wav(List<int> samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // PCM fmt boyutu
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * 2, Endian.little); // byte/sn
  data.setUint16(32, 2, Endian.little); // blok hizası
  data.setUint16(34, 16, Endian.little); // bit/örnek
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
