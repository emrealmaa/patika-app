import 'dart:async';
import 'dart:typed_data';

/// Gözlük kamerasından gelen tek bir kare.
class GlassesFrame {
  /// JPEG baytları (SOI ile başlar, EOI ile biter).
  final Uint8List jpeg;

  /// Telefona ulaştığı (ayrıştırıldığı) an. Tazelik buna göre ölçülür.
  final DateTime receivedAt;

  /// Akış başından beri sıra numarası (atılan kareler de sayılır).
  final int seq;

  const GlassesFrame(this.jpeg, this.receivedAt, this.seq);
}

/// Tazelik ve geri basınç (backpressure): yalnızca EN YENİ kare tutulur.
/// Tüketici yavaşsa eskiler kuyrukta birikmez, yenisi gelince atılır; tazelik
/// süresini aşmış kare hiç verilmez. Saf mantık (saat enjekte edilir).
class LatestFrame {
  final Duration freshness;
  final DateTime Function() _now;

  GlassesFrame? _latest;
  Completer<void>? _waiter;

  /// Hiç tüketilmeden yerine yenisi gelen ya da bayatlayan kareler.
  int dropped = 0;

  LatestFrame({required this.freshness, DateTime Function()? now}) : _now = now ?? DateTime.now;

  void put(GlassesFrame frame) {
    if (_latest != null) dropped++;
    _latest = frame;
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// En yeni kareyi alır (kutu boşalır). Yoksa ya da bayatsa null.
  GlassesFrame? takeFresh() {
    final frame = _latest;
    _latest = null;
    if (frame == null) return null;
    if (_now().difference(frame.receivedAt) > freshness) {
      dropped++;
      return null;
    }
    return frame;
  }

  /// Sıradaki taze kareyi bekler. [clear] çağrılırsa null döner.
  Future<GlassesFrame?> next() async {
    while (true) {
      final fresh = takeFresh();
      if (fresh != null) return fresh;
      final w = _waiter ??= Completer<void>();
      await w.future;
      if (_cleared) {
        _cleared = false;
        return null;
      }
    }
  }

  bool _cleared = false;

  /// Akış durunca: bekleyen tüketici null alır, eldeki kare atılır.
  void clear() {
    _latest = null;
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) {
      _cleared = true;
      w.complete();
    }
  }
}
