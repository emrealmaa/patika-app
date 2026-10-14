import 'dart:async';

import 'frame_source.dart';
import 'synthetic_frames.dart';

/// Ağ ve gözlük olmadan sentetik kare üreten kaynak: kare TÜKETEN kodun
/// (ileride tespit) birim testleri ve Test Modu için. Gözlük zincirinin
/// tamamını (BLE `frm` + Wi-Fi + MJPEG ayrıştırma) denemek için ise
/// `MjpegFrameSource` + `SimulatedMjpegTransport` kullanılır.
class SimulatedFrameSource extends FrameSourceBase {
  SimulatedFrameSource({required super.config, this.interval = const Duration(milliseconds: 100), super.now});

  final Duration interval;
  Timer? _timer;
  int _n = 0;

  @override
  Future<void> start() async {
    if (_timer != null) return;
    resetCounters();
    setState(FrameSourceState.streaming);
    _timer = Timer.periodic(interval, (_) => emit(SyntheticFrames.jpeg(_n++)));
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    latest.clear();
    setState(FrameSourceState.stopped);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
