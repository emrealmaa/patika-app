import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_candidate_source.dart';
import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/motion_sample.dart';
import 'package:patika_app/fall/motion_source.dart';
import 'package:patika_app/fall/synthetic_signals.dart';

/// Faz 7c-1: ivmeölçer kaynağı (native paket çözme, kanal) ve telefon IMU
/// aday kaynağı (başlat/durdur, sensör yalnızca çalışırken açık, kesinti sayımı).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeMotionBatch', () {
    test('Float64List dörtlüleri örneğe çevrilir', () {
      final raw = Float64List.fromList([1000, 0, 9.8, 0, 1020, 0.5, 9.7, 0.1]);
      final out = decodeMotionBatch(raw);
      expect(out, hasLength(2));
      expect(out[1].tMs, 1020);
      expect(out[1].x, 0.5);
      expect(out[1].z, closeTo(0.1, 1e-9));
    });

    test('yarım kalan son dörtlü atılır', () {
      expect(decodeMotionBatch([1000, 0, 9.8, 0, 1020, 0]), hasLength(1));
    });

    test('tanınmayan biçim -> boş liste, çökme yok', () {
      expect(decodeMotionBatch(null), isEmpty);
      expect(decodeMotionBatch('bozuk'), isEmpty);
      expect(decodeMotionBatch([1000, 'x', 9.8, 0]), isEmpty);
    });
  });

  group('MethodChannelMotionSource', () {
    const method = MethodChannel('patika/motion');
    const events = EventChannel('patika/motion_events');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockStreamHandler(events, null);
    });

    test('available: native cevabı; hata -> false', () async {
      messenger.setMockMethodCallHandler(method, (call) async => call.method == 'available');
      expect(await MethodChannelMotionSource().available(), isTrue);
      messenger.setMockMethodCallHandler(method, (_) async => throw PlatformException(code: 'x'));
      expect(await MethodChannelMotionSource().available(), isFalse);
    });

    test('olay kanalından gelen paketler çözülür; dinleme bitince native durur', () async {
      var cancelled = false;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) => sink.success(Float64List.fromList([5000, 0, 9.8, 0])),
          onCancel: (_) => cancelled = true,
        ),
      );
      final first = await MethodChannelMotionSource().samples().first;
      expect(first.single.tMs, 5000);
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });
  });

  group('PhoneImuFallCandidateSource', () {
    late SyntheticMotionSource motion;
    late PhoneImuFallCandidateSource source;
    late List<FallEvaluation> seen;

    setUp(() {
      motion = SyntheticMotionSource();
      source = PhoneImuFallCandidateSource(motion);
      seen = [];
      source.evaluations.listen(seen.add);
    });

    tearDown(() => source.dispose());

    test('başlamadan sensör kapalı; başlayınca açık, durunca kapalı', () async {
      expect(motion.hasListener, isFalse);
      expect(await source.start(), isTrue);
      expect(source.running, isTrue);
      expect(motion.hasListener, isTrue);
      await source.stop();
      expect(source.running, isFalse);
      expect(motion.hasListener, isFalse);
    });

    test('ivmeölçer yoksa başlamaz, sensöre hiç abone olmaz', () async {
      motion.isAvailable = false;
      expect(await source.start(), isFalse);
      expect(source.running, isFalse);
      expect(motion.hasListener, isFalse);
    });

    test('art arda start tek abonelik açar', () async {
      final results = await Future.wait([source.start(), source.start(), source.start()]);
      expect(results, [true, true, true]);
      expect(source.running, isTrue);
    });

    test('örnekler dedektörden geçer, değerlendirmeler yayınlanır', () async {
      await source.start();
      motion.push(syntheticScenario(SyntheticScenario.realisticFall));
      await pumpEventQueue();
      expect(seen.map((e) => e.outcome), [FallOutcome.candidate]);
      expect(source.sourceId, 'phone_imu');
    });

    test('paketlere bölünmüş sinyal de aynı sonucu verir', () async {
      await source.start();
      final all = syntheticScenario(SyntheticScenario.droppedAndPickedUp);
      for (var i = 0; i < all.length; i += 10) {
        motion.push(all.sublist(i, i + 10 > all.length ? all.length : i + 10));
      }
      await pumpEventQueue();
      expect(seen.map((e) => e.outcome), [FallOutcome.movement]);
    });

    test('durdurup yeniden başlatmak kesinti sayılmaz, yarım değerlendirme taşınmaz', () async {
      await source.start();
      final fall = syntheticScenario(SyntheticScenario.realisticFall);
      motion.push(fall.sublist(0, 150)); // düşüş + darbe, sonuç yok
      await pumpEventQueue();
      await source.stop();
      await source.start();
      // Çok sonra gelen örnekler: yeni dedektör, boşluk sayılmaz.
      motion.push([for (final s in fall.sublist(150)) MotionSample(s.tMs + 60000, s.x, s.y, s.z)]);
      await pumpEventQueue();
      expect(seen, isEmpty);
      expect(source.gapCount, 0);
    });

    test('kesintiler yeniden başlatmalar arasında birikir', () async {
      await source.start();
      final b = SignalBuilder(noiseG: 0)
        ..hold(const Duration(seconds: 1), upright)
        ..gap(const Duration(seconds: 2))
        ..hold(const Duration(seconds: 1), upright);
      motion.push(b.samples);
      await pumpEventQueue();
      expect(source.gapCount, 1);
      await source.stop();
      await source.start();
      motion.push(b.samples.map((s) => MotionSample(s.tMs + 100000, s.x, s.y, s.z)).toList());
      await pumpEventQueue();
      expect(source.gapCount, 2);
    });

    test('sensör hatası -> çalışmıyor olur, fırlatmaz', () async {
      await source.start();
      motion.fail(PlatformException(code: 'no_sensor'));
      await pumpEventQueue();
      expect(source.running, isFalse);
      expect(motion.hasListener, isFalse);
    });

    test('sentetik kaynak ayrı adla kurulabilir (gerçek akışa karışmaz)', () async {
      final synthetic = PhoneImuFallCandidateSource(SyntheticMotionSource(), sourceId: 'synthetic');
      expect(synthetic.sourceId, 'synthetic');
      await synthetic.dispose();
    });
  });
}
