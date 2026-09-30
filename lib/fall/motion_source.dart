import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'motion_sample.dart';

/// İvmeölçer örneklerinin kaynağı (Faz 7c). Akışı dinlemek sensörü açar,
/// dinlemeyi bırakmak kapatır: sensör yalnızca biri dinlerken çalışır.
abstract class MotionSource {
  /// Cihazda ivmeölçer var mı? Okunamazsa false.
  Future<bool> available();

  /// Örnek paketleri (zamanca sıralı). Hata olabilir (sensör açılamadı).
  Stream<List<MotionSample>> samples();
}

/// Gerçek kaynak: `MotionProbe.kt` (kanallar `patika/motion`,
/// `patika/motion_events`). İzin gerektirmez.
class MethodChannelMotionSource implements MotionSource {
  static const _method = MethodChannel('patika/motion');
  static const _events = EventChannel('patika/motion_events');

  @override
  Future<bool> available() async {
    try {
      return await _method.invokeMethod<bool>('available') ?? false;
    } catch (e) {
      debugPrint('[Düşme] ivmeölçer sorgulanamadı: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Stream<List<MotionSample>> samples() => _events.receiveBroadcastStream().map(decodeMotionBatch);
}

/// Native paketi çözer: `[t_ms, x, y, z, t_ms, x, y, z, ...]`. Yarım kalan son
/// dörtlü atılır; tanınmayan biçim boş liste (uygulama durmaz).
List<MotionSample> decodeMotionBatch(Object? raw) {
  if (raw is! List) return const [];
  final out = <MotionSample>[];
  for (var i = 0; i + 3 < raw.length; i += 4) {
    final t = raw[i], x = raw[i + 1], y = raw[i + 2], z = raw[i + 3];
    if (t is! num || x is! num || y is! num || z is! num) continue;
    out.add(MotionSample(t.toInt(), x.toDouble(), y.toDouble(), z.toDouble()));
  }
  return out;
}

/// Elle beslenen kaynak: Test Modu'nun sentetik düğmeleri ve testler.
/// Sentetik örnekler gerçek sensör akışına KARIŞTIRILMAZ (zamanları ayrı);
/// bu kaynak ayrı bir aday kaynağına bağlanır ve kayda kendi kaynak adıyla
/// (`synthetic`) girer.
class SyntheticMotionSource implements MotionSource {
  final _controller = StreamController<List<MotionSample>>.broadcast();

  /// Testte "ivmeölçer yok" durumu için.
  bool isAvailable;

  SyntheticMotionSource({this.isAvailable = true});

  /// Şu an dinleyen var mı (sensör "açık" mı)?
  bool get hasListener => _controller.hasListener;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Stream<List<MotionSample>> samples() => _controller.stream;

  /// Örnekleri tek paket olarak verir. Dinleyen yoksa düşer (gerçek sensör
  /// kapalıyken olduğu gibi).
  void push(List<MotionSample> samples) => _controller.add(samples);

  /// Sensör hatası taklidi.
  void fail(Object error) => _controller.addError(error);
}
