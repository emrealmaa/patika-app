import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/ble/ble_connection_state.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/platform/app_version.dart';
import 'package:patika_app/screens/connection_screen.dart';
import 'package:patika_app/screens/listen_screen.dart';
import 'package:patika_app/settings/test_mode_access.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/theme/app_theme.dart';
import 'package:patika_app/voice/voice_controller.dart';
import 'package:patika_app/widgets/mikrofon_hero.dart';
import 'package:patika_app/widgets/nabiz_halkalari.dart';
import 'package:patika_app/widgets/sos_countdown_banner.dart';

import 'fakes.dart';
import 'test_harness.dart';
import 'widget_test.dart' show usePhoneSize;

/// Çalışan (susturulmamış) ticker sayısı: her aktif animasyon bir kare
/// geri çağrısı kaydeder.
int _runningTickers(WidgetTester tester) => tester.binding.transientCallbackCount;

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    );

const _rings = NabizHalkalari(size: 100, color: PatikaTokens.primary);

/// İlk halkanın çapı (animasyon ilerledikçe değişir).
double _firstRingWidth(WidgetTester tester) => tester
    .getSize(find.descendant(of: find.byType(NabizHalkalari), matching: find.byType(Container)).first)
    .width;

void main() {
  group('NabizHalkalari', () {
    testWidgets('çalışır: halkalar büyür; TalkBack\'e girmez', (tester) async {
      await tester.pumpWidget(_host(_rings));
      expect(_runningTickers(tester), greaterThan(0));
      final w0 = _firstRingWidth(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_firstRingWidth(tester), isNot(w0));
      expect(
        find.descendant(of: find.byType(NabizHalkalari), matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
    });

    testWidgets('hareketi azalt açıkken denetleyici çalışmaz, çizim durağan', (tester) async {
      _reduceMotion(tester);
      await tester.pumpWidget(_host(_rings));
      expect(_runningTickers(tester), 0);
      final w0 = _firstRingWidth(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_firstRingWidth(tester), w0);
    });

    testWidgets('ağaçtan çıkınca denetleyici dispose edilir (ticker kalmaz)', (tester) async {
      await tester.pumpWidget(_host(_rings));
      expect(_runningTickers(tester), greaterThan(0));
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      expect(_runningTickers(tester), 0);
    });

    testWidgets('görünmeyen yerde (TickerMode kapalı) ticker susar', (tester) async {
      await tester.pumpWidget(_host(const TickerMode(enabled: false, child: _rings)));
      expect(_runningTickers(tester), 0);
    });
  });

  group('Konuş: dinleme nabzı', () {
    Future<Harness> pump(WidgetTester tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(SizedBox(height: 600, child: MikrofonHero(controller: h.app.voice))));
      return h;
    }

    testWidgets('yalnızca dinlerken çalışır; dinleme bitince durur', (tester) async {
      final h = await pump(tester);
      expect(find.byType(NabizHalkalari), findsNothing);
      expect(_runningTickers(tester), 0);

      h.app.voice.startListening(ListenSource.screen);
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.speech.listening, isTrue);
      expect(find.byType(NabizHalkalari), findsOneWidget);
      expect(_runningTickers(tester), greaterThan(0));

      h.app.voice.cancel();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NabizHalkalari), findsNothing);
      expect(_runningTickers(tester), 0);
    });

    testWidgets('hareketi azalt: dinlerken halkalar durağan, ticker yok', (tester) async {
      _reduceMotion(tester);
      final h = await pump(tester);
      h.app.voice.startListening(ListenSource.screen);
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.speech.listening, isTrue);
      expect(find.byType(NabizHalkalari), findsOneWidget);
      expect(_runningTickers(tester), 0);
      h.app.voice.cancel();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Bağlantı: tarama dalgası', () {
    /// Uygulamada durum değişince HomePage yeniden çizer; tek başına
    /// kurulan ekranda bunu test yapar. Tema BİR KEZ kurulur: her seferinde
    /// yeni ThemeData verilirse MaterialApp'in AnimatedTheme'i tema geçişi
    /// başlatır ve ticker sayımını bozar (uygulamada tema bir kez kurulur).
    final theme = buildAppTheme();
    Future<void> build(WidgetTester tester, Harness h) => tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(body: ConnectionScreen(state: h.app)),
        ));

    Future<Harness> pump(WidgetTester tester) async {
      usePhoneSize(tester);
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      await build(tester, h);
      return h;
    }

    testWidgets('yalnızca tararken çalışır; tarama bitince durur', (tester) async {
      final h = await pump(tester);
      expect(find.byType(NabizHalkalari), findsNothing);

      unawaited(h.app.startScan());
      await build(tester, h);
      expect(h.app.connectionState, BleConnectionState.scanning);
      expect(find.byType(NabizHalkalari), findsOneWidget);
      expect(_runningTickers(tester), greaterThan(0));

      await tester.pump(const Duration(seconds: 1)); // simülatör taramayı bitirir
      await build(tester, h);
      // Düğmelerin etkin/devre dışı renk geçişleri (kısa, örtük) bitsin.
      await tester.pump(const Duration(seconds: 1));
      expect(h.app.connectionState, isNot(BleConnectionState.scanning));
      expect(find.byType(NabizHalkalari), findsNothing);
      expect(_runningTickers(tester), 0);
    });

    testWidgets('hareketi azalt: tararken dalga durağan, ticker yok', (tester) async {
      _reduceMotion(tester);
      final h = await pump(tester);
      unawaited(h.app.startScan());
      await build(tester, h);
      expect(find.byType(NabizHalkalari), findsOneWidget);
      expect(_runningTickers(tester), 0);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('SOS: geri sayım halkası', () {
    const ayse = EmergencyContact('Ayşe Demir', '0555 000 00 03');

    Future<Harness> pump(WidgetTester tester) async {
      usePhoneSize(tester);
      final h = Harness(direct: FakeDirectActions(), emergencyContacts: const [ayse]);
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(SosCountdownBanner(sos: h.app.sos)));
      return h;
    }

    double fraction(WidgetTester tester) => (tester
            .widget<CustomPaint>(find.descendant(
              of: find.byKey(const ValueKey('sos-geri-sayim-halkasi')),
              matching: find.byType(CustomPaint),
            ))
            .painter! as CountdownRingPainter)
        .fraction;

    double target(Harness h) =>
        h.app.sos.status.value.remaining.inMilliseconds / SosConfig.manualCountdown.inMilliseconds;

    Future<void> finish(WidgetTester tester, Harness h) async {
      h.app.sos.cancel(SosCancelSource.screen);
      for (var i = 0; i < 10; i++) {
        h.tts.finishCurrent();
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('değerler arasında yumuşar; hedef her zaman status.remaining', (tester) async {
      final h = await pump(tester);
      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();
      expect(fraction(tester), closeTo(1.0, 0.001));

      // Bir saniyelik tik: hedef 6/7'ye iner, halka oraya kayarak gider.
      await tester.pump(const Duration(seconds: 1));
      final goal = target(h);
      expect(goal, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(fraction(tester), lessThan(1.0));
      expect(fraction(tester), greaterThan(goal));
      await tester.pump(const Duration(milliseconds: 499));
      expect(fraction(tester), closeTo(goal, 0.01));
      await finish(tester, h);
    });

    testWidgets('hareketi azalt: yumuşatma yok, değer anında, ticker yok', (tester) async {
      _reduceMotion(tester);
      final h = await pump(tester);
      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fraction(tester), closeTo(target(h), 0.0001));
      expect(_runningTickers(tester), 0);
      await finish(tester, h);
    });
  });

  testWidgets('SOS ekranı açıkken arkadaki sekmelerde ticker kapalı (TickerMode)', (tester) async {
    usePhoneSize(tester);
    final h = Harness(
      direct: FakeDirectActions(),
      emergencyContacts: const [EmergencyContact('Ayşe Demir', '0555 000 00 03')],
    );
    await tester.pumpWidget(PatikaApp(
      appVersion: const FixedAppVersion(),
      testModeFactory: () => TestModeAccess(store: MemoryTestModeStore()),
      appStateFactory: () => h.app,
    ));
    await tester.pump();
    bool tickersOn() => TickerMode.valuesOf(tester.element(find.byType(ListenScreen))).enabled;
    expect(tickersOn(), isTrue);

    await h.app.sos.trigger(SosSource.glasses);
    await tester.pump();
    expect(h.app.sos.phase, SosPhase.countdown);
    expect(tickersOn(), isFalse);

    h.app.sos.cancel(SosCancelSource.screen);
    await tester.pump();
    expect(tickersOn(), isTrue);

    for (var i = 0; i < 10; i++) {
      h.tts.finishCurrent();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
