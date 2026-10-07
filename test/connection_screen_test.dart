import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/ble/ble_connection_state.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/screens/connection_screen.dart';
import 'package:patika_app/theme/app_theme.dart';

import 'test_harness.dart';

Widget _host(Harness h) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ConnectionScreen(state: h.app)),
    );

void main() {
  group('Bağlantı ekranı', () {
    testWidgets('bağlı değilken durum kartı tek cümle okunur, dalga yok', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(h));

      expect(h.app.connectionState, BleConnectionState.disconnected);
      expect(find.bySemanticsLabel('Bağlantı durumu: Bağlı değil'), findsOneWidget);
      expect(find.byKey(const ValueKey('baglanti-dalgalari')), findsNothing);
      semantics.dispose();
    });

    testWidgets('tararken dalga görünür ama TalkBack\'e girmez', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      unawaited(h.app.startScan());
      await tester.pumpWidget(_host(h));

      expect(h.app.connectionState, BleConnectionState.scanning);
      expect(find.bySemanticsLabel('Bağlantı durumu: Taranıyor…'), findsOneWidget);
      final wave = find.byKey(const ValueKey('baglanti-dalgalari'));
      expect(wave, findsOneWidget);
      expect(find.ancestor(of: wave, matching: find.byType(ExcludeSemantics)), findsWidgets);
      await tester.pump(const Duration(seconds: 1)); // tarama bitsin
      semantics.dispose();
    });

    testWidgets('Bağlan düğmesi: etiket içinde, dokunma eylemi var, en az 56 dp', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      unawaited(h.app.startScan());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(_host(h));
      await tester.pump();

      final device = h.app.devices.first;
      final button = find.widgetWithText(FilledButton, Tr.connect).first;
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.label, Tr.connectTo(device.name));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(PatikaTokens.minTouch));
      semantics.dispose();
    });

    testWidgets('"Nasıl bağlanır?" kısa özetle gelir, adımlar ayrıntıda', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(h));

      expect(find.text(Tr.howToConnectSummary), findsOneWidget);
      expect(find.text(Tr.howToConnectSteps.first), findsNothing);
      await tester.tap(find.text(Tr.detailShow));
      await tester.pump();
      for (final step in Tr.howToConnectSteps) {
        expect(find.text(step), findsOneWidget);
      }
    });
  });
}
