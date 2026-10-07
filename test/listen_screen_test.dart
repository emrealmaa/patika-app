import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/screens/listen_screen.dart';
import 'package:patika_app/theme/app_theme.dart';

import 'test_harness.dart';

Widget _host(Harness h) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ListenScreen(state: h.app)),
    );

void main() {
  group('Konuş ekranı', () {
    testWidgets('gözlük bağlı değil: durum hapı ve gözlük pili kartı bunu söyler', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(h));

      expect(find.bySemanticsLabel('Gözlük bağlı değil'), findsOneWidget);
      expect(find.bySemanticsLabel('Gözlük pili: gözlük bağlı değil'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('bağlı değilken eski gözlük pili gösterilmez', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      addTearDown(h.dispose);
      h.app.glassesBattery = 78; // bağlantı kopmuş, değer kalmış olsa bile
      await tester.pumpWidget(_host(h));

      expect(find.text('%78'), findsNothing);
      expect(find.bySemanticsLabel('Gözlük pili yüzde 78'), findsNothing);
      semantics.dispose();
    });

    testWidgets('telefon pili kartı: yüzde, şarj ve okunamama durumu', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      addTearDown(h.dispose);
      h.app.phoneBatteryPercent = null;
      await tester.pumpWidget(_host(h));
      expect(find.bySemanticsLabel(Tr.statusPhoneUnknown), findsOneWidget);
      expect(find.text(Tr.batteryCardUnknown), findsOneWidget);

      h.app.phoneBatteryPercent = 64;
      h.app.phoneCharging = true;
      await tester.pumpWidget(_host(h));
      expect(find.bySemanticsLabel('Telefon pili yüzde 64, şarj oluyor'), findsOneWidget);
      expect(find.text('%64'), findsOneWidget);
      expect(find.text(Tr.batteryCardCharging), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('ekranda tek düğme var (pil kartları düğme değil)', (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(h));
      expect(find.bySubtype<ButtonStyleButton>(), findsOneWidget);
    });

    testWidgets('küçük ekran ve büyük yazıda taşma yok (kaydırılır)', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = Harness();
      addTearDown(h.dispose);
      h.app.phoneBatteryPercent = 100;
      h.app.phoneCharging = true;
      await tester.pumpWidget(_host(h));
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });
  });
}
