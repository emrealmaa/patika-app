import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/motion_sample.dart';
import 'package:patika_app/fall/synthetic_signals.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/screens/test_mode_screen.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/theme/app_theme.dart';

import 'fakes.dart';
import 'sos_wiring_test.dart' show ayse;
import 'test_harness.dart';

/// Faz 7c-1: Test Modu'ndaki "Düşme algılama (gölge)" bölümü (mod anahtarı,
/// test sesi, sentetik düğmeler, kayıt listesi, silme, sayaçlar).
/// Darbesiz düşüş, ardından 2 sn örnek kesintisi: sayaçlar (1, 1) göstermeli.
List<MotionSample> syntheticNoImpactThenGap() {
  const sec = Duration(seconds: 1);
  return (SignalBuilder(startMs: 500000, noiseG: 0)
        ..hold(sec * 2, upright)
        ..freeFall(const Duration(milliseconds: 300))
        ..hold(sec, lyingFlat)
        ..gap(sec * 2)
        ..hold(sec, lyingFlat))
      .samples;
}

void main() {
  Future<Harness> pumpScreen(
    WidgetTester tester, {
    FakeDirectActions? actions,
    Settings initial = const Settings(fallMode: FallMode.off),
  }) async {
    // Tüm içerik ekran dışına taşmadan oluşturulsun (liste tembel kurar).
    tester.view.physicalSize = const Size(1080, 16000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final h = Harness(
      initial: initial,
      direct: actions ?? const NoDirectActions(),
      emergencyContacts: const [ayse],
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: TestModeScreen(state: h.app))));
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    // Sentetik çalıştırma bir sıfır-süreli zamanlayıcı bekler; kare gerektirmediği
    // için pumpAndSettle onu ilerletmez.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
  }

  group('mod anahtarı', () {
    testWidgets('açınca gölge uyarısı SESLE okunur, sensör açılır; kapatınca kısa bilgi', (tester) async {
      final h = await pumpScreen(tester);
      expect(h.fallMotion.hasListener, isFalse);

      await tapLabel(tester, Tr.testFallMode);
      expect(h.settings.value.fallMode, FallMode.shadow);
      expect(h.tts.spoken, contains(Tr.fallShadowWarning));
      expect(h.app.fall.running, isTrue);
      expect(h.fallMotion.hasListener, isTrue);

      h.tts.finishCurrent(); // uyarı bitti; sıradaki duyuru konuşulabilsin
      await tester.pump();
      await tapLabel(tester, Tr.testFallMode);
      expect(h.settings.value.fallMode, FallMode.off);
      expect(h.tts.spoken, contains(Tr.fallShadowDisabled));
      expect(h.fallMotion.hasListener, isFalse);
    });

    testWidgets('uyarı yalnızca kullanıcı açınca okunur (açılışta sessiz)', (tester) async {
      final h = await pumpScreen(tester, initial: const Settings(fallMode: FallMode.shadow));
      expect(h.app.fall.running, isTrue);
      expect(h.tts.spoken, isNot(contains(Tr.fallShadowWarning)));
    });

    testWidgets('seçim yapılmamışsa anahtar derleme varsayılanını (debug: açık) gösterir', (tester) async {
      await pumpScreen(tester, initial: const Settings());
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, Tr.testFallMode));
      expect(tile.value, isTrue);
    });

    testWidgets('test sesi anahtarı varsayılan kapalı, ayara yazılır', (tester) async {
      final h = await pumpScreen(tester);
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, Tr.testFallEarcon));
      expect(tile.value, isFalse);
      await tapLabel(tester, Tr.testFallEarcon);
      expect(h.settings.value.fallShadowEarcon, isTrue);
    });

    testWidgets('gölgede sensör açılamadıysa ekranda söylenir', (tester) async {
      tester.view.physicalSize = const Size(1080, 16000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final h = Harness(initial: const Settings(fallMode: FallMode.off));
      addTearDown(h.dispose);
      h.fallMotion.isAvailable = false;
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: TestModeScreen(state: h.app))));
      await tester.pumpAndSettle();
      expect(find.text(Tr.testFallSensorUnavailable), findsNothing);
      await tapLabel(tester, Tr.testFallMode);
      expect(find.text(Tr.testFallSensorUnavailable), findsOneWidget);
    });
  });

  group('sentetik düğmeler', () {
    testWidgets('gerçekçi düşme: aday kayda "synthetic" olarak girer, listede ve sonuç satırında görünür',
        (tester) async {
      final h = await pumpScreen(tester);
      expect(find.text(Tr.testFallNoRecords), findsOneWidget);

      await tapLabel(tester, Tr.testFallScenarioRealisticFall);

      expect(h.app.fallLog.records.map((r) => (r.source, r.outcome)), [('synthetic', FallOutcome.candidate)]);
      expect(find.text(Tr.testFallNoRecords), findsNothing);
      expect(find.textContaining('synthetic: ${Tr.fallOutcomeCandidate}', findRichText: true), findsOneWidget);
      expect(
        find.text(Tr.testFallScenarioResult(Tr.testFallScenarioRealisticFall, Tr.fallOutcomeCandidate)),
        findsOneWidget,
      );
    });

    testWidgets('gerçek mod kapalıyken de çalışır; gerçek sensör kapalı kalır, sentetik kaynak işi bitince durur',
        (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      expect(h.app.fall.mode, FallMode.off);
      expect(h.fallMotion.hasListener, isFalse, reason: 'gerçek sensör hiç açılmadı');
      expect(h.app.fallLog.records, hasLength(1));
    });

    testWidgets('gerçek sensör açıkken sentetik örnekler ona karışmaz', (tester) async {
      final h = await pumpScreen(tester, initial: const Settings(fallMode: FallMode.shadow));
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      expect(h.app.fall.gapCount, 0);
      expect(h.app.fall.running, isTrue);
      expect(h.app.fallLog.records.single.source, 'synthetic');
    });

    testWidgets('yürüme ve sert oturma: değerlendirme oluşmaz, kayıt yok', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioWalking);
      expect(find.text(Tr.testFallScenarioResult(Tr.testFallScenarioWalking, Tr.testFallNoEvaluation)),
          findsOneWidget);
      await tapLabel(tester, Tr.testFallScenarioHardSit);
      expect(find.text(Tr.testFallScenarioResult(Tr.testFallScenarioHardSit, Tr.testFallNoEvaluation)),
          findsOneWidget);
      expect(h.app.fallLog.records, isEmpty);
    });

    testWidgets('darbesiz düşüş: sonuç gösterilir ama kayda girmez', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioNoImpact);
      expect(find.text(Tr.testFallScenarioResult(Tr.testFallScenarioNoImpact, Tr.fallOutcomeNoImpact)),
          findsOneWidget);
      expect(h.app.fallLog.records, isEmpty);
    });

    testWidgets('elenenler (hareket sürdü, duruş değişmedi) kayda girer', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioDroppedAndPickedUp);
      await tapLabel(tester, Tr.testFallScenarioNoOrientation);
      expect(h.app.fallLog.records.map((r) => r.outcome),
          [FallOutcome.movement, FallOutcome.noOrientationChange]);
    });

    testWidgets('art arda aynı düğmeye basmak işe yarar (sensör zamanı geri gitmez)', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      expect(h.app.fallLog.records, hasLength(3));
    });

    testWidgets('SOS\'a hiçbir etkisi yok (gerçek acil kişi tanımlıyken bile)', (tester) async {
      final actions = FakeDirectActions();
      final h = await pumpScreen(tester, actions: actions);
      var changes = 0;
      h.app.sos.status.addListener(() => changes++);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      await tester.pump(const Duration(seconds: 60));
      expect(h.app.fallLog.records, hasLength(1));
      expect(h.app.sos.phase, SosPhase.idle);
      expect(h.app.sos.history, isEmpty);
      expect(changes, 0);
      expect(actions.sms, isEmpty);
      expect(actions.calls, isEmpty);
    });
  });

  group('kayıt listesi ve silme', () {
    testWidgets('en yeni üstte, en fazla 20 satır', (tester) async {
      final h = await pumpScreen(tester);
      for (var i = 0; i < 25; i++) {
        await h.app.fallLog.add(
          FallEvaluation(
            outcome: FallOutcome.movement,
            startMs: 0,
            freeFallMs: 100 + i,
            peakG: 3,
            orientationDegrees: 80,
            stillnessStdG: 0.3,
          ),
          source: 'phone_imu',
        );
      }
      await tester.pumpAndSettle();
      final lines = find.textContaining('phone_imu: ${Tr.fallOutcomeMovement}', findRichText: true);
      expect(lines, findsNWidgets(20));
      // En yeni (düşüş 124 ms) en üstte, en eski 5 kayıt (100-104) listede yok.
      final first = tester.getTopLeft(find.textContaining('Düşüş 124 ms')).dy;
      final last = tester.getTopLeft(find.textContaining('Düşüş 105 ms')).dy;
      expect(first, lessThan(last));
      expect(find.textContaining('Düşüş 104 ms'), findsNothing);
    });

    testWidgets('kayıt satırında konum ya da ham veri yok: yalnızca özet değerler', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      final text = tester
          .widgetList<Text>(find.textContaining('synthetic:'))
          .map((t) => t.data ?? '')
          .join();
      expect(text, contains('Düşüş'));
      expect(text, contains('tepe'));
      expect(text, contains('derece'));
      expect(text.toLowerCase(), isNot(contains('konum')));
      expect(h.app.fallLog.records, hasLength(1));
    });

    testWidgets('"Kayıtları sil" kaydı ve dosyayı siler, sesle söyler', (tester) async {
      final h = await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioRealisticFall);
      expect(h.fallLogStore.content, isNotNull);

      await tapLabel(tester, Tr.testFallClear);
      expect(h.app.fallLog.records, isEmpty);
      expect(h.fallLogStore.content, isNull);
      expect(find.text(Tr.testFallNoRecords), findsOneWidget);
      expect(h.tts.spoken, contains(Tr.testFallCleared));
    });
  });

  group('sayaçlar', () {
    testWidgets('darbesiz düşüş ve sensör kesintisi sayaçta görünür', (tester) async {
      final h = await pumpScreen(tester, initial: const Settings(fallMode: FallMode.shadow));
      expect(find.text(Tr.testFallCounters(0, 0)), findsOneWidget);

      // Gerçek akışa darbesiz düşüş + ardından kesinti.
      final scenario = syntheticNoImpactThenGap();
      h.fallMotion.push(scenario);
      await tester.pumpAndSettle();
      expect(find.text(Tr.testFallCounters(1, 1)), findsOneWidget);
    });
  });

  group('erişilebilirlik', () {
    testWidgets('bölümün her düğmesi ve anahtarı dokunma eylemi taşır, en az 56 dp', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);

      final labels = [
        Tr.testFallScenarioRealisticFall,
        Tr.testFallScenarioDroppedAndPickedUp,
        Tr.testFallScenarioHardSit,
        Tr.testFallScenarioNoImpact,
        Tr.testFallScenarioNoOrientation,
        Tr.testFallScenarioWalking,
        Tr.testFallClear,
      ];
      for (final label in labels) {
        final button = find.widgetWithText(OutlinedButton, label);
        expect(button, findsOneWidget, reason: label);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: '$label TalkBack ile tetiklenemiyor');
        expect(tester.getSize(button).height, greaterThanOrEqualTo(56), reason: label);
      }
      for (final label in [Tr.testFallMode, Tr.testFallEarcon]) {
        final tile = find.widgetWithText(SwitchListTile, label);
        expect(tester.getSemantics(tile).getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: label);
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(56), reason: label);
      }
      semantics.dispose();
    });

    testWidgets('sonuç satırı canlı bölge (TalkBack sonucu kendiliğinden okur)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await tapLabel(tester, Tr.testFallScenarioWalking);
      final node = tester.getSemantics(find.text(
        Tr.testFallScenarioResult(Tr.testFallScenarioWalking, Tr.testFallNoEvaluation),
      ));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });
  });
}
