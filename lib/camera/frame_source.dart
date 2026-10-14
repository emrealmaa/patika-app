import 'dart:async';

import 'package:flutter/foundation.dart';

import 'camera_config.dart';
import 'glasses_frame.dart';

/// Kare kaynağının durumu.
enum FrameSourceState {
  stopped,

  /// `frm on` gönderildi / ağ ve akış bekleniyor.
  starting,

  /// Kareler geliyor.
  streaming,

  /// Akış istendi ama kare gelmiyor (ağ koptu ya da akış durdu). Ağ geri
  /// gelince kendiliğinden devam eder.
  interrupted,

  /// Başlatılamadı (gözlük bağlı değil, ağ reddedildi vb.). Yeniden [start].
  failed,
}

/// Tek kare kaynağı arayüzü: gözlük MJPEG'i, simülasyon ya da ileride başka
/// bir kaynak (patika Python roadmap'indeki "tek FrameSource arayüzü" fikri).
/// Tüketici ya [frames] akışını dinler (her kare) ya da [latest]'ten yalnızca
/// en yeni TAZE kareyi alır (yavaş tüketici: eskiler birikmez).
abstract class FrameSource {
  ValueListenable<FrameSourceState> get state;
  Stream<GlassesFrame> get frames;
  LatestFrame get latest;

  /// Akış başından beri teslim edilen kare sayısı.
  int get delivered;

  Future<void> start();
  Future<void> stop();
  void dispose();
}

/// Ortak kısım: durum, kare akışı, tazelik kutusu, kare hızı sınırı.
abstract class FrameSourceBase implements FrameSource {
  final CameraConfig config;
  final DateTime Function() now;

  FrameSourceBase({required this.config, DateTime Function()? now})
      : now = now ?? DateTime.now {
    latest = LatestFrame(freshness: config.freshness, now: this.now);
  }

  final _state = ValueNotifier<FrameSourceState>(FrameSourceState.stopped);
  final _frames = StreamController<GlassesFrame>.broadcast();

  @override
  late final LatestFrame latest;

  @override
  ValueListenable<FrameSourceState> get state => _state;

  @override
  Stream<GlassesFrame> get frames => _frames.stream;

  int _seq = 0;
  int _delivered = 0;
  DateTime? _lastDelivered;

  /// Kare hızı sınırına takılıp atılan kareler.
  int throttled = 0;

  @override
  int get delivered => _delivered;

  @protected
  void setState(FrameSourceState value) => _state.value = value;

  @protected
  void resetCounters() {
    _seq = 0;
    _delivered = 0;
    throttled = 0;
    _lastDelivered = null;
    latest.dropped = 0;
  }

  /// Ayrıştırılmış bir JPEG'i teslim eder ([CameraConfig.maxFps] sınırıyla).
  /// Teslim edildiyse true.
  @protected
  bool emit(Uint8List jpeg) {
    final at = now();
    final seq = _seq++;
    final last = _lastDelivered;
    if (last != null && at.difference(last) < config.minFrameInterval) {
      throttled++;
      return false;
    }
    _lastDelivered = at;
    _delivered++;
    final frame = GlassesFrame(jpeg, at, seq);
    latest.put(frame);
    if (!_frames.isClosed) _frames.add(frame);
    return true;
  }

  @override
  @mustCallSuper
  void dispose() {
    latest.clear();
    _frames.close();
    _state.dispose();
  }
}
