import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/camera/camera_config.dart';
import 'package:patika_app/camera/frame_source.dart';
import 'package:patika_app/camera/glasses_control_socket.dart';
import 'package:patika_app/camera/glasses_frame.dart';
import 'package:patika_app/camera/mjpeg_frame_source.dart';
import 'package:patika_app/camera/mjpeg_parser.dart';
import 'package:patika_app/camera/simulated_frame_source.dart';
import 'package:patika_app/camera/synthetic_frames.dart';
import 'package:patika_app/glasses_wifi/glasses_wifi_service.dart';
import 'package:patika_app/l10n/strings_tr.dart';

import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// Madde 2: gözlük kamerası görüntü kanalı. Kilitlenenler: MJPEG ayrıştırıcı
/// (bozuk/yarım kare, sınır kayması, büyük kare), tazelik + geri basınç,
/// kare hızı sınırı, `frm` kodlama, Wi-Fi durum makinesiyle entegrasyon
/// (kopunca akış durur, geri gelince devam eder), sesli bildirimler.
void main() {
  const b = 'frame';
  Uint8List jpeg(int seq, {int padding = 0}) => SyntheticFrames.jpeg(seq, padding: padding);
  List<int> part(Uint8List j, {bool withLength = true}) =>
      SyntheticFrames.part(j, b, withLength: withLength);
  String seqOf(Uint8List j) => latin1.decode(j.sublist(6, j.length - 2)).trim();

  group('MjpegParser', () {
    test('tek parçada birden çok kare', () {
      final p = MjpegParser(boundary: b);
      final out = p.add([...part(jpeg(0)), ...part(jpeg(1)), ...part(jpeg(2))]);
      expect(out.map(seqOf), ['patika-sim-0', 'patika-sim-1', 'patika-sim-2']);
      expect(p.dropped, 0);
    });

    test('bayt bayt gelen akış aynı kareleri verir', () {
      final p = MjpegParser(boundary: b);
      final stream = [...part(jpeg(0)), ...part(jpeg(1), withLength: false), ...part(jpeg(2))];
      final out = <Uint8List>[];
      for (final byte in stream) {
        out.addAll(p.add([byte]));
      }
      expect(out.map(seqOf), ['patika-sim-0', 'patika-sim-1', 'patika-sim-2']);
    });

    test('Content-Length yoksa SOI..EOI arası kare', () {
      final p = MjpegParser(boundary: b);
      final out = p.add([...part(jpeg(5), withLength: false), ...part(jpeg(6), withLength: false)]);
      expect(out.map(seqOf), ['patika-sim-5', 'patika-sim-6']);
    });

    test('sınır bilinmiyorsa yalnızca SOI..EOI taranır', () {
      final p = MjpegParser();
      final out = p.add([1, 2, 3, ...jpeg(1), 9, 9, ...jpeg(2)]);
      expect(out.map(seqOf), ['patika-sim-1', 'patika-sim-2']);
    });

    test('ilk sınırdan önceki çöp atlanır', () {
      final p = MjpegParser(boundary: b);
      final out = p.add([...latin1.encode('HTTP çöp\r\n'), ...part(jpeg(3))]);
      expect(out.map(seqOf), ['patika-sim-3']);
    });

    test('yanlış Content-Length (sınır kayması): kare atılır, sonraki sınırda hizalanır', () {
      final p = MjpegParser(boundary: b);
      final bad = latin1.encode('--$b\r\nContent-Length: 7\r\n\r\n') + jpeg(0) + latin1.encode('\r\n');
      final out = p.add([...bad, ...part(jpeg(1))]);
      expect(out.map(seqOf), ['patika-sim-1']);
      expect(p.dropped, 1);
    });

    test('yarım kare (EOI gelmeden yeni parça) atılır', () {
      final p = MjpegParser(boundary: b);
      final full = jpeg(0);
      final half = latin1.encode('--$b\r\n\r\n') + full.sublist(0, full.length - 3);
      final out = p.add([...half, ...part(jpeg(1), withLength: false)]);
      expect(out.map(seqOf), ['patika-sim-1']);
      expect(p.dropped, 1);
    });

    test('JPEG olmayan gövde atılır', () {
      final p = MjpegParser(boundary: b);
      final notJpeg = Uint8List.fromList(latin1.encode('merhaba dunya'));
      final out = p.add([...part(notJpeg), ...part(jpeg(2))]);
      expect(out.map(seqOf), ['patika-sim-2']);
      expect(p.dropped, 1);
    });

    test('büyük kare parça parça gelir ve bütün çıkar', () {
      final p = MjpegParser(boundary: b);
      final big = jpeg(9, padding: 300 * 1024);
      final stream = part(big);
      final out = <Uint8List>[];
      for (var i = 0; i < stream.length; i += 4096) {
        out.addAll(p.add(stream.sublist(i, i + 4096 > stream.length ? stream.length : i + 4096)));
      }
      expect(out, hasLength(1));
      expect(out.single.length, big.length);
    });

    test('sınırdan büyük kare atılır, akış sürer (uzunluklu ve uzunluksuz)', () {
      final p = MjpegParser(boundary: b, maxFrameBytes: 1024);
      final out = p.add([
        ...part(jpeg(0, padding: 4096)),
        ...part(jpeg(1)),
        ...part(jpeg(2, padding: 4096), withLength: false),
        ...part(jpeg(3)),
      ]);
      expect(out.map(seqOf), ['patika-sim-1', 'patika-sim-3']);
      expect(p.dropped, 2);
    });

    test('Content-Type içinden sınır', () {
      expect(MjpegParser.boundaryFromContentType('multipart/x-mixed-replace; boundary=frame'), 'frame');
      expect(MjpegParser.boundaryFromContentType('multipart/x-mixed-replace;boundary="--abc"'), 'abc');
      expect(MjpegParser.boundaryFromContentType('image/jpeg'), isNull);
      expect(MjpegParser.boundaryFromContentType(null), isNull);
    });
  });

  group('tazelik ve geri basınç', () {
    final t0 = DateTime(2026, 1, 1);
    GlassesFrame frame(int seq, int ms) =>
        GlassesFrame(jpeg(seq), t0.add(Duration(milliseconds: ms)), seq);

    test('yavaş tüketici en yeni kareyi alır, eskiler atılır', () {
      var now = t0;
      final box = LatestFrame(freshness: const Duration(milliseconds: 400), now: () => now);
      box
        ..put(frame(0, 0))
        ..put(frame(1, 10))
        ..put(frame(2, 20));
      now = t0.add(const Duration(milliseconds: 30));
      expect(box.takeFresh()!.seq, 2);
      expect(box.dropped, 2);
      expect(box.takeFresh(), isNull, reason: 'kutu boşaldı');
    });

    test('tazelik süresini aşan kare verilmez', () {
      var now = t0;
      final box = LatestFrame(freshness: const Duration(milliseconds: 400), now: () => now);
      box.put(frame(0, 0));
      now = t0.add(const Duration(milliseconds: 401));
      expect(box.takeFresh(), isNull);
      expect(box.dropped, 1);
    });

    test('next() sıradaki kareyi bekler; clear() bekleyeni bırakır', () async {
      final box = LatestFrame(freshness: const Duration(seconds: 1));
      final waiting = box.next();
      box.put(GlassesFrame(jpeg(4), DateTime.now(), 4));
      expect((await waiting)!.seq, 4);
      final pending = box.next();
      box.clear();
      expect(await pending, isNull);
    });

    test('kare hızı sınırı: daha sık gelen kareler atılır', () {
      fakeAsync((async) {
        final t = DateTime(2026);
        final src = SimulatedFrameSource(
          config: const CameraConfig(maxFps: 5),
          interval: const Duration(milliseconds: 100),
          now: () => t.add(async.elapsed),
        );
        src.start();
        async.elapse(const Duration(milliseconds: 1000));
        expect(src.delivered, 5);
        expect(src.throttled, 5);
        src.stop();
        expect(src.state.value, FrameSourceState.stopped);
        src.dispose();
      });
    });
  });

  group('frm (taslak)', () {
    test('kodlama ve çözme', () {
      expect(utf8.decode(GlassesProtocol.encodeFrm(true)), '{"t":"frm","on":true}');
      expect(GlassesProtocol.decodeFrm(GlassesProtocol.encodeFrm(false)), isFalse);
      expect(GlassesProtocol.decodeFrm(utf8.encode('{"t":"hb"}')), isNull);
      expect(GlassesProtocol.decodeFrm(utf8.encode('bozuk')), isNull);
      // 21-22 bayt: MTU pazarlığı başarısız olursa (20 bayt) sığmaz - belgede açık nokta.
      expect(GlassesProtocol.encodeFrm(false).length, lessThanOrEqualTo(244));
    });
  });

  group('uygulamada (simülasyon zinciri)', () {
    /// Gözlüğe (simüle) bağlanır.
    void connectGlasses(Harness h, FakeAsync async) {
      h.app.connect('SIM-ESP32-S3-0001');
      async.elapse(const Duration(seconds: 1));
      h.speakAll(async);
      h.tts.spoken.clear();
    }

    /// Saniye saniye ilerler, konuşmaları bitirir.
    void run(Harness h, FakeAsync async, int ms) {
      for (var i = 0; i < ms; i += 100) {
        async.elapse(const Duration(milliseconds: 100));
        h.speakAll(async);
      }
    }

    MjpegFrameSource source(Harness h, FakeAsync async) {
      final t = DateTime(2026);
      return MjpegFrameSource(
        config: const CameraConfig(),
        sendFrm: (on) => h.app.bleService.setCameraStream(on),
        wifi: h.app.glassesWifi,
        transport: () => h.app.cameraSimTransport,
        feedback: h.app.feedback,
        now: () => t.add(async.elapsed),
      );
    }

    test('frm -> ağ bilgisi -> Wi-Fi -> kareler; kopunca durur, gelince sürer', () {
      fakeAsync((async) {
        final h = Harness();
        connectGlasses(h, async);
        final cam = source(h, async);
        cam.start();
        run(h, async, 2000);
        expect(h.app.simulator!.cameraStreamOn, isTrue);
        expect(h.app.glassesWifi.status.value.state, GlassesWifiState.connected);
        expect(cam.state.value, FrameSourceState.streaming);
        expect(cam.delivered, greaterThan(3));
        expect(h.tts.spoken.first, Tr.cameraStarting);
        expect(h.tts.spoken, contains(Tr.glassesCameraConnected));
        expect(h.tts.spoken.last, Tr.cameraStreaming);
        expect(cam.parseErrors, 0);

        h.tts.spoken.clear();
        h.app.wifiSimulator!.drop();
        run(h, async, 500);
        expect(cam.state.value, FrameSourceState.interrupted);
        final before = cam.delivered;
        run(h, async, 5000);
        expect(cam.delivered, before, reason: 'ağ yokken kare yok');
        expect(h.tts.spoken, [Tr.glassesCameraLost], reason: 'kopma bir kez, akış ayrıca konuşmaz');

        h.app.wifiSimulator!.restore();
        run(h, async, 1000);
        expect(cam.state.value, FrameSourceState.streaming);
        expect(cam.delivered, greaterThan(before));
        expect(h.tts.spoken, [Tr.glassesCameraLost, Tr.glassesCameraConnected]);

        h.tts.spoken.clear();
        cam.stop();
        run(h, async, 300);
        expect(h.app.simulator!.cameraStreamOn, isFalse);
        expect(h.app.glassesWifi.status.value.state, GlassesWifiState.idle);
        expect(h.tts.spoken, [Tr.cameraStopped], reason: 'Wi-Fi ayrıca "kapatıldı" demez');
        cam.dispose();
        h.dispose();
      });
    });

    test('ağ açıkken kare gelmezse bir kez "görüntü gelmiyor", dönünce "geri geldi"', () {
      fakeAsync((async) {
        final h = Harness();
        connectGlasses(h, async);
        final cam = source(h, async);
        cam.start();
        run(h, async, 2000);
        h.tts.spoken.clear();

        h.app.cameraSimTransport.stalled = true;
        run(h, async, 10000);
        expect(cam.state.value, FrameSourceState.interrupted);
        expect(h.tts.spoken, [Tr.cameraStalled]);

        h.app.cameraSimTransport.stalled = false;
        run(h, async, 500);
        expect(cam.state.value, FrameSourceState.streaming);
        expect(h.tts.spoken, [Tr.cameraStalled, Tr.cameraResumed]);
        cam.dispose();
        h.dispose();
      });
    });

    test('gözlük bağlı değilse başlatılamaz, nedeni söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.camera.start();
        run(h, async, 500);
        expect(h.app.camera.state.value, FrameSourceState.failed);
        expect(h.tts.spoken, [Tr.cameraStarting, Tr.cameraNoGlasses]);
        h.app.camera.stop();
        run(h, async, 300);
        expect(h.tts.spoken.last, Tr.cameraNoGlasses, reason: 'başarısızlıktan sonra "kapatıldı" denmez');
        h.dispose();
      });
    });

    test('gözlük ağ bilgisini göndermezse zaman aşımı söylenir, frm off gider', () {
      fakeAsync((async) {
        final h = Harness();
        final sent = <bool>[];
        final cam = MjpegFrameSource(
          config: const CameraConfig(),
          sendFrm: (on) async {
            sent.add(on);
            return true;
          },
          wifi: h.app.glassesWifi,
          transport: () => h.app.cameraSimTransport,
          feedback: h.app.feedback,
        );
        cam.start();
        run(h, async, 11000);
        expect(cam.state.value, FrameSourceState.failed);
        expect(h.tts.spoken.last, Tr.cameraNoCredentials);
        expect(sent, [true, false]);
        cam.dispose();
        h.dispose();
      });
    });

    test('onay reddedilirse akış başarısız; nedeni Wi-Fi söyler', () {
      fakeAsync((async) {
        final h = Harness();
        connectGlasses(h, async);
        h.app.wifiSimulator!.declineNext = true;
        final cam = source(h, async);
        cam.start();
        run(h, async, 2000);
        expect(cam.state.value, FrameSourceState.failed);
        expect(h.tts.spoken.last, Tr.glassesCameraDeclined);
        expect(h.app.simulator!.cameraStreamOn, isFalse, reason: 'gözlük boşuna kamera açık tutmaz');
        cam.dispose();
        h.dispose();
      });
    });
  });

  test('WebSocket kanalı yazılmadı: açıkça UnimplementedError', () {
    expect(() => const UnimplementedGlassesControlSocket().connect(Uri.parse('ws://x')),
        throwsUnimplementedError);
  });

  test('strings_tr.dart kamera bölümü yasaklı kelime içermez', () {
    final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
    const header = '// --- Gözlük kamerası: görüntü akışı';
    final start = source.indexOf(header);
    expect(start, greaterThanOrEqualTo(0));
    final next = source.indexOf('\n  // --- ', start + 10);
    final section = source.substring(start, next == -1 ? source.length : next);
    final code = section.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    final literals =
        RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!).toList();
    expect(literals.length, greaterThanOrEqualTo(7));
    for (final text in literals) {
      expect(bannedIn(text), isEmpty, reason: '"$text"');
    }
  });
}
