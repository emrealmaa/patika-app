import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/simulated_walk.dart';

import 'fakes.dart';
import 'widget_test.dart' show testApp;

void main() {
  group('RouteWalker', () {
    test('başlangıçta rotanın başında; 200 m sonra ilk adımın sonunda', () {
      final route = demoRoute();
      final walker = RouteWalker(route);
      expect(distanceMeters(walker.position, route.start), lessThan(0.5));

      walker.advance(200);
      expect(distanceMeters(walker.position, route.steps[1].points.first), lessThan(0.5));
    });

    test('rotanın sonunda durur, geri gitmez', () {
      final route = demoRoute();
      final walker = RouteWalker(route)..advance(10000);
      expect(walker.atEnd, isTrue);
      expect(distanceMeters(walker.position, route.end), lessThan(0.5));
      walker.advance(-10000);
      expect(walker.offset, 0);
    });

    test('offRoute: rotaya dik 40 m yanda', () {
      final route = demoRoute();
      final walker = RouteWalker(route)..advance(100);
      final off = walker.offRoute(40);
      final seg = projectOnSegment(off, route.steps[0].points[0], route.steps[0].points[1]);
      expect(seg.distance, closeTo(40, 0.5));
    });
  });

  test('demo rotası motorla: aynı olay sırası (dönüş x2, geçiş, varış)', () {
    final route = demoRoute();
    final engine = GuidanceEngine(route, config: const GuidanceConfig(directionCheck: false));
    final walker = RouteWalker(route);
    final events = <GuidanceEvent>[];
    var t = DateTime(2026, 9, 28, 12);
    while (!walker.atEnd && !engine.isFinished) {
      walker.advance(10);
      t = t.add(const Duration(seconds: 1));
      events.addAll(engine.update(PositionFix(walker.position, 5, t)));
    }
    expect(events.map((e) => e.runtimeType).toList(), [
      ManeuverAhead,
      ManeuverAhead,
      CrossingAhead,
      CrossingPoint,
      CrossingResumed,
      NearDestination,
      Arrived,
    ]);
  });

  testWidgets('Test Modu: navigasyon simülasyonu deneme rotasında duyuru üretir',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 16000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final tts = FakeSpeechOutput();
    await tester.pumpWidget(testApp(tts: tts));
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();
    expect(find.text('Navigasyon durumu: çalışmıyor'), findsOneWidget);

    await tester.tap(find.text('Deneme rotasını başlat'));
    await tester.pumpAndSettle();
    expect(find.text('Navigasyon durumu: çalışıyor'), findsOneWidget);
    expect(tts.spoken.single,
        'Deneme hedefi, 450 metre, yaklaşık 6 dakika. Rota Deneme Caddesi boyunca 200 metre. '
        'Yön bilgisi yürümeye başlayınca gelecek');

    for (var i = 0; i < 3; i++) {
      tts.finishCurrent();
      await tester.tap(find.text('Rotada 50 metre yürü'));
      await tester.pumpAndSettle();
    }
    tts.finishCurrent();
    await tester.pump();
    expect(tts.spoken.any((s) => s.contains('sonra rota sağa sapıyor, Örnek Sokak')), isTrue,
        reason: tts.spoken.join(' | '));

    // Zamanlayıcı kalmasın.
    await tester.tap(find.text('Navigasyonu bitir'));
    await tester.pumpAndSettle();
    expect(find.text('Navigasyon durumu: çalışmıyor'), findsOneWidget);
  });
}
