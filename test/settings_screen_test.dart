import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/screens/settings_screen.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/theme/app_theme.dart';

import 'test_harness.dart';
import 'widget_test.dart' show testApp, usePhoneSize;

/// TalkBack'in gezeceği sırayla, etiketi olan ilk anlamsal düğüm.
SemanticsNode? _firstLabeled(SemanticsNode node) {
  if (node.label.isNotEmpty && !node.isInvisible) return node;
  for (final child in node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
    final found = _firstLabeled(child);
    if (found != null) return found;
  }
  return null;
}

void _expectFirstFocusIsHeader(WidgetTester tester, String title) {
  final root = tester.getSemantics(find.byType(Scaffold).first);
  final first = _firstLabeled(root);
  expect(first, isNotNull);
  expect(first!.label, title);
  expect(first.getSemanticsData().flagsCollection.isHeader, isTrue, reason: '$title başlık değil');
}

void main() {
  group('ekran başlıkları: TalkBack\'te ilk odak', () {
    testWidgets('üst çubuk yok; Konuş, Bağlantı, Ayarlar başlıkla başlar', (tester) async {
      final semantics = tester.ensureSemantics();
      usePhoneSize(tester);
      await tester.pumpWidget(testApp());
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      _expectFirstFocusIsHeader(tester, Tr.screenTitleListen);

      await tester.tap(find.text(Tr.tabConnection));
      await tester.pumpAndSettle();
      _expectFirstFocusIsHeader(tester, Tr.screenTitleConnection);

      await tester.tap(find.text(Tr.tabSettings));
      await tester.pumpAndSettle();
      _expectFirstFocusIsHeader(tester, Tr.screenTitleSettings);
      semantics.dispose();
    });

    testWidgets('TalkBack kipinde Konuş: önce başlık, sonra tek büyük düğme', (tester) async {
      final semantics = tester.ensureSemantics();
      usePhoneSize(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(testApp());
      await tester.pump();

      _expectFirstFocusIsHeader(tester, Tr.screenTitleListen);
      expect(find.bySubtype<ButtonStyleButton>(), findsOneWidget);
      semantics.dispose();
    });
  });

  group('Ayarlar', () {
    Future<Harness> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 16000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsScreen(
            store: h.settings,
            feedback: h.app.feedback,
            onStartTutorial: () {},
          ),
        ),
      ));
      return h;
    }

    testWidgets('112 ceza uyarısı özette görünür (ayrıntıya saklanmaz)', (tester) async {
      await pump(tester);
      expect(find.text(Tr.sosCall112Summary), findsOneWidget);
      expect(Tr.sosCall112Summary, contains('idari para cezası'));
      expect(Tr.sosCall112Details.join(' '), isNot(contains('ceza')));
    });

    testWidgets('112 anahtarı varsayılan kapalı ve toggled durumunu bildirir', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pump(tester);
      expect(h.settings.value.emergencyCall112, isFalse);
      expect(
        tester.getSemantics(find.bySemanticsLabel(Tr.sosCall112Title)),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      semantics.dispose();
    });

    testWidgets('anahtarın altındaki ayrıntı düğmesi hangi ayara ait olduğunu söyler',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(find.bySemanticsLabel('Ayrıntıyı göster: ${Tr.muteNotifications}'), findsOneWidget);
      expect(find.bySemanticsLabel('Ayrıntıyı göster: ${Tr.sosCall112Title}'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('"SOS nasıl çalışır?" özet ve ayrıntıyı gösterir', (tester) async {
      await pump(tester);
      final summary = Tr.sosHowSummary(SosConfig.manualCountdown.inSeconds);
      expect(find.text(summary), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Ayrıntıyı göster: ${Tr.sosHowTitle}'));
      await tester.pump();
      for (final line in Tr.sosHowDetails) {
        expect(find.text(line), findsOneWidget);
      }
    });
  });

  // Karttaki bilgi koddaki karara birebir uymalı (CLAUDE.md Faz 7 madde 2).
  group('"SOS nasıl çalışır?" metni koddaki kararla aynı', () {
    test('geri sayım süresi SosConfig\'ten (7 sn)', () {
      expect(SosConfig.manualCountdown, const Duration(seconds: 7));
      expect(Tr.sosHowSummary(SosConfig.manualCountdown.inSeconds), contains('7 saniye'));
    });

    test('kartta sayılan her iptal sözcüğü gerçekten iptal eder', () {
      for (final word in Tr.sosHowCancelWords) {
        expect(classifySosVoice(word), SosVoiceCommand.cancel, reason: word);
      }
    });

    test('"dur" iptal etmez ve kart bunu söyler', () {
      expect(classifySosVoice('dur'), isNot(SosVoiceCommand.cancel));
      expect(Tr.sosHowDetails, contains('"Dur" demek geri sayımı iptal etmez.'));
    });

    test('hiçbir şey yapılmazsa gönderilir: özet ve ayrıntı bunu söyler', () {
      expect(Tr.sosHowSummary(7), contains('iptal etmezseniz acil kişilerinize gönderilir'));
      expect(Tr.sosHowDetails, contains('Hiçbir şey yapmazsanız mesaj acil kişilerinize gönderilir.'));
    });
  });
}
