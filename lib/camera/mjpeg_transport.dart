import 'dart:async';

import 'package:flutter/services.dart';

import 'synthetic_frames.dart';

/// Ham MJPEG akış olayları (ayrıştırma `MjpegParser`'da).
sealed class MjpegEvent {
  const MjpegEvent();
}

class MjpegHeader extends MjpegEvent {
  final String? contentType;
  const MjpegHeader(this.contentType);
}

class MjpegChunk extends MjpegEvent {
  final Uint8List bytes;
  const MjpegChunk(this.bytes);
}

/// Gözlükteki MJPEG adresine bağlanır. Dönen akış dinlendikçe bağlantı açık
/// kalır; dinleme iptal edilince kapanır. Akış biterse (sunucu kapattı, ağ
/// koptu) `onDone`/`onError` gelir.
abstract class MjpegTransport {
  Stream<MjpegEvent> open(String url);
}

/// Gerçek taşıma: `GlassesMjpegStream.kt` (EventChannel `patika/glasses_mjpeg`),
/// istek GÖZLÜK AĞI üzerinden gider (bkz. `GlassesNetwork.kt`).
class NativeMjpegTransport implements MjpegTransport {
  static const channelName = 'patika/glasses_mjpeg';
  static const _channel = EventChannel(channelName);

  const NativeMjpegTransport();

  @override
  Stream<MjpegEvent> open(String url) => _channel
      .receiveBroadcastStream({'url': url})
      .map(_parse)
      .where((e) => e != null)
      .cast<MjpegEvent>();

  static MjpegEvent? _parse(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'header' => MjpegHeader(raw['contentType'] as String?),
      'chunk' when raw['bytes'] is Uint8List => MjpegChunk(raw['bytes'] as Uint8List),
      _ => null,
    };
  }
}

/// Simülasyon taşıması: sentetik kareleri gerçek bir MJPEG bayt akışı
/// (sınır + başlık + kare) olarak üretir; böylece Test Modu'nda ayrıştırıcı
/// dahil tüm zincir çalışır. [stalled] iken bağlantı açık kalır ama veri
/// gelmez (gözlük donması).
class SimulatedMjpegTransport implements MjpegTransport {
  static const boundary = 'patikaframe';

  final Duration interval;

  /// Ağ bağlı değilken açılırsa hemen hata (gerçekteki "noNetwork").
  final bool Function() networkUp;

  SimulatedMjpegTransport({
    this.interval = const Duration(milliseconds: 100),
    bool Function()? networkUp,
  }) : networkUp = networkUp ?? _always;

  static bool _always() => true;

  bool stalled = false;
  int opened = 0;
  int _seq = 0;

  @override
  Stream<MjpegEvent> open(String url) {
    opened++;
    late StreamController<MjpegEvent> controller;
    Timer? timer;
    controller = StreamController<MjpegEvent>(
      onListen: () {
        if (!networkUp()) {
          controller.addError(StateError('noNetwork'));
          controller.close();
          return;
        }
        controller.add(const MjpegHeader('multipart/x-mixed-replace; boundary=$boundary'));
        timer = Timer.periodic(interval, (_) {
          if (stalled) return;
          final part = SyntheticFrames.part(SyntheticFrames.jpeg(_seq++), boundary);
          // Gerçek ağdaki gibi parçalı: kare iki pakete bölünür.
          final mid = part.length ~/ 2;
          controller
            ..add(MjpegChunk(Uint8List.fromList(part.sublist(0, mid))))
            ..add(MjpegChunk(Uint8List.fromList(part.sublist(mid))));
        });
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}
