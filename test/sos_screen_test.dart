import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/platform/app_version.dart';
import 'package:patika_app/settings/test_mode_access.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/widgets/sos_countdown_banner.dart';

import 'fakes.dart';
import 'test_harness.dart';
import 'widget_test.dart' show usePhoneSize;

const _ayse = EmergencyContact('Ayşe Demir', '0555 000 00 03');
const _ali = EmergencyContact('Ali Kaya', '0555 000 00 02');

/// Gerçek arama/SMS yok: FakeDirectActions (112 koruması testlerle kilitli).
Harness _direct() => Harness(direct: FakeDirectActions(), emergencyContacts: const [_ayse, _ali]);

/// Uygulamanın tamamı (sekmeler + alt çubuk + SOS ekranı). AppState'i
/// HomePage kapatır; ayrıca h.dispose çağrılmaz.
Widget _app(Harness h) => PatikaApp(
      appVersion: const FixedAppVersion(),
      testModeFactory: () => TestModeAccess(store: MemoryTestModeStore()),
      appStateFactory: () => h.app,
    );

/// Gerçek anlamsal ağaçta (kökten) arar. `find.bySemanticsLabel` render
/// nesnesinde kalan eski veriye bakar, BlockSemantics ile düşen düğümleri de
/// bulabilir; bu yüzden engelleme testinde kullanılmaz.
int _inTree(Pattern label) => find.semantics.byLabel(label).evaluate().length;

Future<void> _speakAll(WidgetTester tester, Harness h) async {
  for (var i = 0; i < 20; i++) {
    h.tts.finishCurrent();
    await tester.pump();
  }
}

/// Testin sonunda bekleyen zamanlayıcı kalmasın.
Future<void> _teardown(WidgetTester tester, Harness h) async {
  if (h.app.sos.inCountdown) h.app.sos.cancel(SosCancelSource.screen);
  await _speakAll(tester, h);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  group('SOS tam ekranı', () {
    testWidgets('açılınca arkadaki sekmeler ve alt çubuk TalkBack\'ten düşer (BlockSemantics)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      usePhoneSize(tester);
      final h = _direct();
      await tester.pumpWidget(_app(h));
      await tester.pump();

      // Önce: sekmeler ve ekran başlığı TalkBack'te.
      expect(_inTree(RegExp('Sekme ')), greaterThan(0));
      expect(_inTree(Tr.screenTitleListen), 1);

      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();
      expect(h.app.sos.phase, SosPhase.countdown);

      // Açıkken: arkadaki widget'lar duruyor ama TalkBack onlara gidemez.
      expect(find.text(Tr.tabListen), findsOneWidget);
      expect(_inTree(RegExp('Sekme ')), 0);
      expect(_inTree(Tr.screenTitleListen), 0);
      expect(_inTree(Tr.voiceButtonLabel), 0);
      // SOS ekranının kendisi okunur: başlık ve iptal düğmesi.
      expect(_inTree(Tr.sosBannerTitle(7)), 1);
      expect(_inTree(Tr.sosCancelButton), 1);

      // İptal edilince sekmeler geri gelir.
      await tester.tap(find.widgetWithText(FilledButton, Tr.sosCancelButton));
      await tester.pump();
      expect(h.app.sos.phase, SosPhase.idle);
      expect(_inTree(RegExp('Sekme ')), greaterThan(0));

      await _teardown(tester, h);
      semantics.dispose();
    });

    testWidgets('iptal düğmesi en az 64 dp; ekranda "Şimdi gönder" ve kişi adı yok',
        (tester) async {
      usePhoneSize(tester);
      final h = _direct();
      await tester.pumpWidget(_app(h));
      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();

      final button = find.widgetWithText(FilledButton, Tr.sosCancelButton);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(64));
      // Yalnızca SOS ekranının içi (arkadaki Konuş ekranında örnek cümle
      // "Ayşe'yi ara" var; o SOS ekranı değil).
      Finder onSosScreen(String text) => find.descendant(
            of: find.byType(SosCountdownBanner),
            matching: find.textContaining(text),
          );
      expect(onSosScreen('Şimdi gönder'), findsNothing);
      for (final c in [_ayse, _ali]) {
        expect(onSosScreen(c.name.split(' ').first), findsNothing, reason: c.name);
      }
      expect(find.text(Tr.sosBannerTitle(7)), findsOneWidget);

      await _teardown(tester, h);
    });

    testWidgets('tam ekran açıkken sesle "iptal" yine iptal eder; TTS duyuruları sürer',
        (tester) async {
      usePhoneSize(tester);
      final h = _direct();
      await tester.pumpWidget(_app(h));
      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();
      expect(h.tts.spoken, contains(Tr.sosCountdownStart));

      await _speakAll(tester, h);
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.speech.listening, isTrue, reason: 'giriş cümlesi bitince "iptal" için dinler');

      h.speech.say('iptal');
      await tester.pump();
      await _speakAll(tester, h);
      expect(h.app.sos.phase, SosPhase.idle);
      expect(h.tts.spoken.last, Tr.sosCancelled);
      expect(find.byType(FilledButton), findsNothing);

      await _teardown(tester, h);
    });

    // Hareketi azalt açık: yumuşatma yok, halka her tikte tam olarak
    // status.remaining'i gösterir. (Adım 7'de halkaya değerler arası
    // yumuşatma eklendi; animasyonlu hali animations_test.dart'ta.)
    testWidgets('halka status.remaining\'den çizilir (kendi zamanlayıcısı yok) ve süs',
        (tester) async {
      usePhoneSize(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final h = _direct();
      await tester.pumpWidget(_app(h));
      await h.app.sos.trigger(SosSource.glasses);
      await tester.pump();

      final ringFinder = find.byKey(const ValueKey('sos-geri-sayim-halkasi'));
      expect(ringFinder, findsOneWidget);
      expect(find.ancestor(of: ringFinder, matching: find.byType(ExcludeSemantics)), findsWidgets);

      double fraction() => (tester
              .widget<CustomPaint>(
                find.descendant(of: ringFinder, matching: find.byType(CustomPaint)),
              )
              .painter! as CountdownRingPainter)
          .fraction;
      double expected() =>
          h.app.sos.status.value.remaining.inMilliseconds / SosConfig.manualCountdown.inMilliseconds;

      expect(fraction(), closeTo(1.0, 0.001));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(h.app.sos.status.value.remaining, lessThan(SosConfig.manualCountdown));
      expect(fraction(), closeTo(expected(), 0.001));
      expect(find.text('${h.app.sos.status.value.remaining.inSeconds}'), findsOneWidget);

      await _teardown(tester, h);
    });
  });

  test('halka çizeri: oran değişince yeniden çizer', () {
    const a = CountdownRingPainter(fraction: 1);
    expect(a.shouldRepaint(const CountdownRingPainter(fraction: 1)), isFalse);
    expect(a.shouldRepaint(const CountdownRingPainter(fraction: 0.5)), isTrue);
  });
}
