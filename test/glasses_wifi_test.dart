import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/ble/simulated_ble_service.dart';
import 'package:patika_app/glasses_wifi/glasses_wifi_controller.dart';
import 'package:patika_app/glasses_wifi/glasses_wifi_service.dart';
import 'package:patika_app/glasses_wifi/simulated_glasses_wifi_service.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/screens/test_mode_screen.dart';

import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// Madde 1: gözlük SoftAP'ına uygulamaya özel Wi-Fi bağlantısı. Kilitlenenler:
/// - taslak `wifi` BLE mesajı (SSID/parola) ayrıştırılır, bozuğu atlanır;
/// - bağlanma yalnızca açıkça istenince, sesli yönlendirmeden sonra;
/// - her sonuç söylenir, kopma sessiz geçmez, aynı durum iki kez söylenmez;
/// - Android 10 altı, Wi-Fi kapalı, izin reddi nedenleriyle söylenir;
/// - Google/navigasyon kodu gözlük ağı kanalını hiç kullanmaz; native taraf
///   süreci ağa bağlamaz (`bindProcessToNetwork` yok).
void main() {
  List<int> bytes(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

  group('protokol: wifi mesajı (taslak)', () {
    test('SSID + parola', () {
      final m = GlassesProtocol.decode(bytes({'t': 'wifi', 'ssid': 'Patika-1A2B', 'pass': 'parola-1234'}));
      expect(m, isA<WifiCredentialsMessage>());
      expect((m as WifiCredentialsMessage).credentials,
          const GlassesWifiCredentials('Patika-1A2B', 'parola-1234'));
    });

    test('parolasız SoftAP', () {
      final m = GlassesProtocol.decode(bytes({'t': 'wifi', 'ssid': 'Patika-1A2B'}));
      expect((m as WifiCredentialsMessage).credentials.passphrase, isNull);
    });

    test('bozuk mesajlar atlanır', () {
      for (final bad in <Map<String, Object?>>[
        {'t': 'wifi'},
        {'t': 'wifi', 'ssid': ''},
        {'t': 'wifi', 'ssid': 42},
        {'t': 'wifi', 'ssid': 'a' * 33},
        {'t': 'wifi', 'ssid': 'Patika', 'pass': 'kisa'},
        {'t': 'wifi', 'ssid': 'Patika', 'pass': 'x' * 64},
        {'t': 'wifi', 'ssid': 'Patika', 'pass': 12345678},
      ]) {
        expect(GlassesProtocol.decode(bytes(bad)), isNull, reason: '$bad');
      }
    });

    test('toString parolayı göstermez', () {
      expect(const GlassesWifiCredentials('Patika', 'gizli-parola').toString(),
          isNot(contains('gizli')));
    });

    test('native durum dizgisi çözülür; tanınmayan yok sayılır', () {
      expect(MethodChannelGlassesWifiService.parseNativeStatus('connected', null),
          const GlassesWifiStatus(GlassesWifiState.connected));
      expect(MethodChannelGlassesWifiService.parseNativeStatus('unavailable', 'wifiOff'),
          const GlassesWifiStatus(
              GlassesWifiState.unavailable, GlassesWifiUnavailableReason.wifiOff));
      expect(MethodChannelGlassesWifiService.parseNativeStatus('unavailable', null)!.reason,
          GlassesWifiUnavailableReason.error);
      expect(MethodChannelGlassesWifiService.parseNativeStatus('lost', 'wifiOff')!.reason, isNull);
      expect(MethodChannelGlassesWifiService.parseNativeStatus('bilinmez', null), isNull);
    });
  });

  group('uygulamada (simülasyon)', () {
    const connectingFirst = '${Tr.glassesCameraConnecting}. ${Tr.glassesCameraApprovalHint}';

    /// Bekleyen konuşmaları bitirip onay penceresi gecikmesini geçer.
    void settle(Harness h, FakeAsync async) {
      h.speakAll(async);
      async.elapse(const Duration(seconds: 1));
      h.speakAll(async);
    }

    test('gözlük ağ bilgisini BLE ile gönderir; kendiliğinden bağlanılmaz', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(h.app.glassesWifi.credentials, isNotNull);
        expect(h.app.wifiSimulator!.connectCalls, 0);
        expect(h.tts.spoken, isEmpty);
        h.dispose();
      });
    });

    test('ağ bilgisi yokken bağlanılmaz, nedeni söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken, [Tr.glassesCameraNoCredentials]);
        expect(h.app.wifiSimulator!.connectCalls, 0);
        h.dispose();
      });
    });

    test('bağlanma: önce sesli yönlendirme, sonra istek; sonuç söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        async.flushMicrotasks();
        h.app.glassesWifi.connect();
        async.flushMicrotasks();
        expect(h.tts.spoken, [connectingFirst]);
        expect(h.app.wifiSimulator!.connectCalls, 0,
            reason: 'onay penceresi konuşma bitmeden açılmaz');
        settle(h, async);
        expect(h.app.wifiSimulator!.connectCalls, 1);
        expect(h.tts.spoken.last, Tr.glassesCameraConnected);
        expect(h.app.glassesWifi.status.value.state, GlassesWifiState.connected);

        // İkinci bağlanmada uzun yönlendirme yok (spam değil).
        h.app.glassesWifi.disconnect();
        settle(h, async);
        expect(h.tts.spoken.last, Tr.glassesCameraClosed);
        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken, contains(Tr.glassesCameraConnecting));
        expect(h.tts.spoken.where((s) => s == connectingFirst), hasLength(1));
        h.dispose();
      });
    });

    test('onay reddedilince söylenir, yeniden denenebilir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        h.app.wifiSimulator!.declineNext = true;
        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken.last, Tr.glassesCameraDeclined);
        expect(h.app.glassesWifi.status.value.state, GlassesWifiState.userDeclined);

        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken.last, Tr.glassesCameraConnected);
        h.dispose();
      });
    });

    test('kopma yüksek öncelikle söylenir, geri gelince "bağlandı"; tekrar yok', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        h.app.glassesWifi.connect();
        settle(h, async);
        h.tts.spoken.clear();

        h.app.wifiSimulator!.drop();
        h.app.wifiSimulator!.drop(); // aynı durum: ikinci kez söylenmez
        settle(h, async);
        expect(h.tts.spoken, [Tr.glassesCameraLost]);

        h.app.wifiSimulator!.restore();
        settle(h, async);
        expect(h.tts.spoken, [Tr.glassesCameraLost, Tr.glassesCameraConnected]);
        h.dispose();
      });
    });

    test('Wi-Fi kapalıysa nedeni söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        h.app.wifiSimulator!.unavailableNext = GlassesWifiUnavailableReason.wifiOff;
        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken.last, Tr.glassesCameraWifiOff);
        h.dispose();
      });
    });

    test('Android 10 altı: istek yapılmaz, nedeni söylenir', () {
      fakeAsync((async) {
        late SimulatedGlassesWifiService sim;
        final h = Harness(
          glassesWifiFactory: (_) => sim = SimulatedGlassesWifiService(
            supportResult: const GlassesWifiSupport(supported: false, needsNearbyPermission: false),
          ),
        );
        h.app.simulator!.injectWifiCredentials();
        async.flushMicrotasks();
        h.app.glassesWifi.connect();
        settle(h, async);
        expect(h.tts.spoken, [Tr.glassesCameraUnsupported]);
        expect(sim.connectCalls, 0);
        expect(h.app.glassesWifi.status.value.reason, GlassesWifiUnavailableReason.unsupported);
        h.dispose();
      });
    });
  });

  group('izin (Android 13+)', () {
    const creds = GlassesWifiCredentials('Patika-1A2B', 'parola-1234');

    test('izin gerekmiyorsa hiç sorulmaz', () {
      fakeAsync((async) {
        final h = Harness();
        var asked = 0;
        final sim = SimulatedGlassesWifiService();
        final c = GlassesWifiController(
          feedback: h.app.feedback,
          service: sim,
          ensurePermission: () async {
            asked++;
            return true;
          },
        )..updateCredentials(creds);
        c.connect();
        h.speakAll(async);
        expect(asked, 0);
        expect(sim.connectCalls, 1);
        c.dispose();
        sim.dispose();
        h.dispose();
      });
    });

    test('reddedilirse istek yapılmaz ve nedeni söylenir; verilirse bağlanır', () {
      fakeAsync((async) {
        final h = Harness();
        var granted = false;
        final sim = SimulatedGlassesWifiService(
          supportResult: const GlassesWifiSupport(supported: true, needsNearbyPermission: true),
        );
        final c = GlassesWifiController(
          feedback: h.app.feedback,
          service: sim,
          ensurePermission: () async => granted,
        )..updateCredentials(creds);
        c.connect();
        h.speakAll(async);
        expect(sim.connectCalls, 0);
        expect(h.tts.spoken, [Tr.glassesCameraPermissionDenied]);
        expect(c.status.value.reason, GlassesWifiUnavailableReason.permission);

        granted = true;
        c.connect();
        h.speakAll(async);
        expect(sim.connectCalls, 1);
        expect(sim.lastCredentials, creds);
        c.dispose();
        sim.dispose();
        h.dispose();
      });
    });
  });

  test('SOS araması sürerken duyuru bekletilir, sonra söylenir', () {
    fakeAsync((async) {
      final h = Harness();
      var calling = false;
      final sim = SimulatedGlassesWifiService(approvalDelay: Duration.zero);
      final c = GlassesWifiController(
        feedback: h.app.feedback,
        service: sim,
        ensurePermission: () async => true,
        holdSpeech: () => calling,
      )..updateCredentials(const GlassesWifiCredentials('Patika-1A2B'));
      c.connect();
      h.speakAll(async);
      async.elapse(Duration.zero);
      h.speakAll(async);
      h.tts.spoken.clear();

      calling = true;
      sim.drop();
      h.speakAll(async);
      expect(h.tts.spoken, isEmpty);
      c.flushHeld();
      expect(h.tts.spoken, isEmpty, reason: 'arama sürüyor');

      calling = false;
      c.flushHeld();
      h.speakAll(async);
      expect(h.tts.spoken, [Tr.glassesCameraLost]);
      c.dispose();
      sim.dispose();
      h.dispose();
    });
  });

  test('simülasyon <-> gerçek geçişi Wi-Fi servisini de değiştirir', () async {
    final created = <bool>[];
    final h = Harness(realBleFactory: SimulatedBleService.new, glassesWifiFactory: (simulated) {
      created.add(simulated);
      return SimulatedGlassesWifiService();
    });
    h.app.simulator!.injectWifiCredentials();
    await Future<void>.delayed(Duration.zero);
    expect(h.app.glassesWifi.credentials, isNotNull);
    await h.app.toggleMode(false);
    expect(created, [true, false]);
    expect(h.app.glassesWifi.credentials, isNull, reason: 'başka gözlüğün ağ bilgisi taşınmaz');
    h.dispose();
  });

  testWidgets('Test Modu: ağ bilgisi gönderilir, bağlanılır, kopma taklit edilir', (tester) async {
    final h = Harness();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TestModeScreen(state: h.app))));
    Future<void> tap(String label) async {
      final finder = find.text(label);
      await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(finder);
      await tester.pump();
    }

    await tap(Tr.testGlassesWifiSendCredentials);
    expect(h.app.glassesWifi.credentials, SimulatedBleService.simulatedWifi);
    await tap(Tr.testGlassesWifiConnect);
    h.tts.finishCurrent();
    await tester.pump(const Duration(seconds: 1));
    expect(h.app.wifiSimulator!.connectCalls, 1);
    expect(find.text(Tr.testGlassesWifiState(Tr.glassesWifiStateName('connected'))), findsOneWidget);

    await tap(Tr.testGlassesWifiDrop);
    expect(h.app.glassesWifi.status.value.state, GlassesWifiState.lost);
    expect(find.text(Tr.testGlassesWifiState(Tr.glassesWifiStateName('lost'))), findsOneWidget);
    h.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  group('kaynak taraması', () {
    Iterable<File> dartFiles(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('navigasyon ve Google istemcileri gözlük ağını hiç kullanmaz', () {
      for (final f in dartFiles('lib/navigation')) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('glasses_wifi')), reason: f.path);
        expect(src, isNot(contains('GlassesWifi')), reason: f.path);
      }
    });

    test('gözlük ağı kanalı yalnızca lib/glasses_wifi/ içinde', () {
      for (final f in dartFiles('lib')) {
        final inModule = f.path.replaceAll('\\', '/').contains('lib/glasses_wifi/');
        if (inModule) continue;
        expect(f.readAsStringSync(), isNot(contains("'patika/glasses_wifi'")), reason: f.path);
      }
    });

    test('native taraf süreci gözlük ağına bağlamaz, interneti istemez', () {
      final kotlinDir = Directory('android/app/src/main/kotlin');
      for (final f in kotlinDir.listSync(recursive: true).whereType<File>()) {
        final code = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('*') && !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code, isNot(contains('bindProcessToNetwork')), reason: f.path);
        expect(code, isNot(contains('setProcessDefaultNetwork')), reason: f.path);
      }
      final net = File('android/app/src/main/kotlin/com/patika/patika_app/GlassesNetwork.kt')
          .readAsStringSync();
      expect(net, contains('WifiNetworkSpecifier'));
      expect(net, contains('removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)'));
    });

    test('manifest: yakındaki Wi-Fi izni konum için kullanılmaz', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.ACCESS_WIFI_STATE'));
      final i = manifest.indexOf('android.permission.NEARBY_WIFI_DEVICES');
      expect(i, greaterThan(0));
      expect(manifest.substring(i, i + 120), contains('neverForLocation'));
    });
  });

  test('strings_tr.dart "Gözlük kamerası" bölümü yasaklı kelime içermez', () {
    final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
    const header = '// --- Gözlük kamerası: Wi-Fi bağlantısı';
    final start = source.indexOf(header);
    expect(start, greaterThanOrEqualTo(0));
    final next = source.indexOf('\n  // --- ', start + 10);
    final section = source.substring(start, next == -1 ? source.length : next);
    final code = section.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    final literals =
        RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!).toList();
    expect(literals.length, greaterThan(8));
    for (final text in literals) {
      expect(bannedIn(text), isEmpty, reason: '"$text"');
    }
    for (final reason in [null, ...GlassesWifiUnavailableReason.values]) {
      expect(bannedIn(GlassesWifiController.unavailableText(reason)), isEmpty);
    }
  });
}
