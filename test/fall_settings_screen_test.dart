import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_consent_store.dart';
import 'package:patika_app/fall/fall_enable_session.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_open_gate.dart';
import 'package:patika_app/fall/fall_open_state.dart';
import 'package:patika_app/fall/fall_settings_controller.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/screens/settings_screen.dart';

import 'test_harness.dart';

/// Faz 7c-2, adım 4: Ayarlar ekranındaki "Düşme algılama (deneysel)" bölümü
/// ve "Anladım, aç" penceresi (ekran kanalı). Tüm kurallar `FallEnableSession`
/// testlerinde; burada ekranın davranışı, erişilebilirlik ve "TalkBack varsa
/// yalnızca TalkBack, yoksa TTS" kuralı denenir.
void main() {
  late Harness h;
  late MemoryFallOpenState state;
  late FallMode mode;
  late List<FallMode> setCalls;
  late int contacts;
  late bool sms;
  late DateTime? since;
  late int records;
  late FallSettingsController controller;
  late FallEnableSession session;

  void build({ShadowGatePolicy policy = const ShadowGatePolicy()}) {
    session = FallEnableSession(
      gate: FallOpenModeGate(
        directBuild: () async => true,
        contactCount: () async => contacts,
        hasSmsPermission: () async => sms,
        shadowSince: () async => since,
        policy: policy,
      ),
      state: state,
      consent: MemoryFallConsentStore(),
      currentMode: () => mode,
      setMode: (m) async {
        setCalls.add(m);
        mode = m;
      },
    );
    controller = FallSettingsController(
      session: session,
      mode: () => mode,
      setMode: (m) async {
        setCalls.add(m);
        mode = m;
      },
      state: state,
      recordCount: () => records,
    );
  }

  setUp(() {
    h = Harness();
    state = MemoryFallOpenState(since: DateTime.now().subtract(const Duration(days: 8, hours: 1)));
    since = state.since;
    mode = FallMode.shadow;
    setCalls = [];
    contacts = 1;
    sms = true;
    records = 2;
    build();
  });

  tearDown(() {
    session.cancel(); // 120 sn'lik oturum zamanlayıcısı testten sonra kalmasın
    h.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, {bool withFall = true}) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 120 sn'lik oturum zamanlayıcısı, pencere açık kalan testlerde de temizlensin.
    addTearDown(() => session.cancel());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsScreen(
          store: h.settings,
          feedback: h.app.feedback,
          onStartTutorial: () {},
          fall: withFall ? controller : null,
        ),
      ),
    ));
    await tester.pump();
  }

  void talkBack(WidgetTester tester, bool on) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(accessibleNavigation: on);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Finder openButton() => find.widgetWithText(FilledButton, Tr.fallOpenButtonOpen);
  Finder closeButton() => find.widgetWithText(FilledButton, Tr.fallOpenButtonClose);

  testWidgets('bağımlılık verilmezse bölüm hiç görünmez', (tester) async {
    await pumpScreen(tester, withFall: false);
    expect(find.text(Tr.fallSettingsSection), findsNothing);
    expect(find.text(Tr.fallOpenButtonOpen), findsNothing);
  });

  testWidgets('bölüm başlığı, durum satırı (gün + kayıt), anahtar ve düğme görünür', (tester) async {
    await pumpScreen(tester);
    expect(find.text(Tr.fallSettingsSection), findsOneWidget);
    expect(find.text(Tr.fallStatusShadowLine(8, 2)), findsOneWidget);
    expect(find.text(Tr.fallShadowSwitchTitle), findsOneWidget);
    expect(openButton(), findsOneWidget);
  });

  testWidgets('durum satırı kapalıyken ve açıkken yazıyla söyler (renkle değil)', (tester) async {
    mode = FallMode.off;
    await pumpScreen(tester);
    expect(find.text(Tr.fallStatusOffLine), findsOneWidget);

    mode = FallMode.on;
    controller.changed();
    await tester.pump();
    await tester.pump();
    expect(find.text(Tr.fallStatusOnLine(8, 2)), findsOneWidget);
    expect(closeButton(), findsOneWidget);
  });

  group('gölge anahtarı', () {
    testWidgets('açınca gölgeye geçer ve uyarıyı SESLE okur (TalkBack kapalı)', (tester) async {
      mode = FallMode.off;
      await pumpScreen(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      await tester.pump();
      expect(mode, FallMode.shadow);
      expect(h.tts.spoken, contains(Tr.fallShadowWarning));
      expect(find.text(Tr.fallShadowWarning), findsOneWidget, reason: 'yazıyla da görünür');
    });

    testWidgets('kapatınca TAMAMEN kapanır (açık moddayken de), tek adımda', (tester) async {
      mode = FallMode.on;
      await pumpScreen(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      await tester.pump();
      expect(mode, FallMode.off);
      expect(setCalls, [FallMode.off]);
      expect(h.tts.spoken, contains(Tr.fallShadowDisabled));
    });

    testWidgets('bekleyen açma varsa anahtar onu da iptal eder', (tester) async {
      await pumpScreen(tester);
      await session.begin(FallEnableChannel.screen);
      expect(session.pending, isTrue);
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(session.pending, isFalse);
    });
  });

  group('"Açık modu aç" düğmesi', () {
    testWidgets('engellenmişken düğme ETKİN kalır; basınca neden yazılır ve söylenir', (tester) async {
      contacts = 0;
      await pumpScreen(tester);
      expect(tester.widget<FilledButton>(openButton()).onPressed, isNotNull);

      await tester.tap(openButton());
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenBlockedNoContacts), findsOneWidget);
      expect(h.tts.spoken, contains(Tr.fallOpenBlockedNoContacts));
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('her engel nedeni ses diyaloğuyla AYNI metni kullanır', (tester) async {
      await pumpScreen(tester);
      sms = false;
      await tester.tap(openButton());
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenBlockedNoSms), findsOneWidget);

      sms = true;
      since = DateTime.now().subtract(const Duration(days: 2));
      await tester.tap(openButton());
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenBlockedShadow(5)), findsOneWidget);
    });

    testWidgets('kapılar tamamsa pencere açılır: tam uyarı, iki düğme, MOD HENÜZ AÇILMADI', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(Tr.fallOpenDialogTitle), findsOneWidget);
      expect(find.text(Tr.fallOpenWarningFull), findsOneWidget);
      expect(find.text(Tr.fallOpenDialogConfirm), findsOneWidget);
      expect(find.text(Tr.fallOpenDialogCancel), findsOneWidget);
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(session.pendingChannel, FallEnableChannel.screen);
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('varsayılan odak "Vazgeç"; dokunma eylemi ve en az 56 dp', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();

      final cancel = find.widgetWithText(TextButton, Tr.fallOpenDialogCancel);
      final confirm = find.widgetWithText(FilledButton, Tr.fallOpenDialogConfirm);
      expect(tester.widget<TextButton>(cancel).autofocus, isTrue);
      expect(tester.widget<FilledButton>(confirm).autofocus, isFalse);
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(confirm).height, greaterThanOrEqualTo(56));
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('"Vazgeç": açılmaz, bekleyen iptal, bayrak yazılmaz', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(Tr.fallOpenDialogCancel));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(session.pending, isFalse);
      expect(state.heard, isFalse);
      expect(find.text(Tr.fallOpenNotEnabled), findsOneWidget);
    });

    testWidgets('geri tuşu da vazgeçmektir (bekleyen iptal)', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(session.pending, isFalse);
      expect(mode, FallMode.shadow);
    });

    testWidgets('"Anladım, aç": mod açılır, bayrak yazılır, düğme "Açık modu kapat" olur', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(Tr.fallOpenDialogConfirm));
      await tester.pumpAndSettle();

      expect(mode, FallMode.on);
      expect(setCalls, [FallMode.on]);
      expect(state.heard, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(Tr.fallOpenEnabled), findsOneWidget);
      expect(closeButton(), findsOneWidget);
    });

    testWidgets('sonraki açışta KISA hatırlatma (tam metin değil), yine iki adım', (tester) async {
      state.heard = true;
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(find.text(Tr.fallOpenWarningShort), findsOneWidget);
      expect(find.text(Tr.fallOpenWarningFull), findsNothing);
      expect(mode, FallMode.shadow);
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('pencere açıkken acil kişi silinirse onay açmaz ve nedeni söyler', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      contacts = 0;
      await tester.tap(find.text(Tr.fallOpenDialogConfirm));
      await tester.pumpAndSettle();
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(find.text(Tr.fallOpenBlockedNoContacts), findsOneWidget);
    });

    testWidgets('pencere 120 sn açık kalırsa onay açmaz: süre doldu', (tester) async {
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      await tester.pump(FallEnableSession.timeout);
      await tester.tap(find.text(Tr.fallOpenDialogConfirm));
      await tester.pumpAndSettle();
      expect(mode, FallMode.shadow);
      expect(find.text(Tr.fallOpenExpired), findsOneWidget);
    });

    testWidgets('açıkken düğmenin TAM etiketi "gölge modu sürer" der (Semantics dahil) ve gölgeyi tamamen kapatmanın ayrı yolu hatırlatılır', (tester) async {
      final handle = tester.ensureSemantics();
      mode = FallMode.on;
      await pumpScreen(tester);
      expect(Tr.fallOpenButtonClose, 'Açık modu kapat (gölge modu sürer)');
      expect(closeButton(), findsOneWidget);
      expect(tester.getSemantics(closeButton()).label, Tr.fallOpenButtonClose);
      expect(find.widgetWithText(FilledButton, 'Kapat'), findsNothing, reason: 'yalnızca "Kapat" etiketi yok');
      // Gölgeyi tamamen kapatmanın ayrı yolu yazıyla hatırlatılır ve gerçekten var:
      expect(find.text(Tr.fallOpenCloseNote), findsOneWidget);
      expect(find.text(Tr.fallShadowSwitchTitle), findsOneWidget);
      expect(Tr.fallOpenCloseNote, contains(Tr.fallShadowSwitchTitle));
      // Kapalı/gölgedeyken bu not yok (açık modu anlatan ipucu var).
      mode = FallMode.shadow;
      controller.changed();
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenCloseNote), findsNothing);
      expect(find.text(Tr.fallOpenButtonHint), findsOneWidget);
      handle.dispose();
    });

    testWidgets('açıkken "Açık modu kapat": tek adım, gölgeye düşer', (tester) async {
      mode = FallMode.on;
      await pumpScreen(tester);
      await tester.tap(closeButton());
      await tester.pump();
      await tester.pump();
      expect(mode, FallMode.shadow);
      expect(setCalls, [FallMode.shadow]);
      expect(find.text(Tr.fallOpenClosedToShadow), findsOneWidget);
    });
  });

  group('TalkBack ve TTS çakışmaz (karar 3)', () {
    testWidgets('TalkBack KAPALI: uyarıyı TTS okur; pencere kapanınca konuşma kesilir', (tester) async {
      talkBack(tester, false);
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(h.tts.spoken.where((t) => t.contains(Tr.fallOpenWarningFull)), hasLength(1));
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('TalkBack AÇIK: uyarıyı yalnızca TalkBack okur (TTS susar), metin ekranda', (tester) async {
      talkBack(tester, true);
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(find.text(Tr.fallOpenWarningFull), findsOneWidget);
      expect(h.tts.spoken, isEmpty);
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('TalkBack AÇIK: engel nedeni yalnızca yazıyla (canlı bölge), TTS susar', (tester) async {
      talkBack(tester, true);
      contacts = 0;
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenBlockedNoContacts), findsOneWidget);
      expect(h.tts.spoken, isEmpty);
      final live = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.liveRegion == true);
      expect(live, isNotEmpty);
    });

    testWidgets('TalkBack KAPALI: engel nedeni hem yazılır hem söylenir', (tester) async {
      talkBack(tester, false);
      contacts = 0;
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pump();
      await tester.pump();
      expect(find.text(Tr.fallOpenBlockedNoContacts), findsOneWidget);
      expect(h.tts.spoken, contains(Tr.fallOpenBlockedNoContacts));
    });
  });

  group('debug 7 gün atlaması izi', () {
    testWidgets('atlanırsa pencerede görünür not var ve TTS uyarının başında söyler', (tester) async {
      since = null;
      build(policy: const ShadowGatePolicy(debugSkip: true));
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(find.text(Tr.fallGateBypassedNote), findsOneWidget);
      expect(h.tts.spoken.any((t) => t.startsWith(Tr.fallGateBypassedNote)), isTrue);
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });

    testWidgets('süre yeterliyse not yok', (tester) async {
      build(policy: const ShadowGatePolicy(debugSkip: true));
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(find.text(Tr.fallGateBypassedNote), findsNothing);
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });
  });

  group('erişilebilirlik', () {
    testWidgets('bölümün düğmesi ve anahtarı dokunma eylemi taşır, en az 56 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(tester.getSize(openButton()).height, greaterThanOrEqualTo(56));
      final switchTile = find.widgetWithText(SwitchListTile, Tr.fallShadowSwitchTitle);
      expect(tester.getSize(switchTile).height, greaterThanOrEqualTo(56));
      expect(
        tester.getSemantics(openButton()),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: Tr.fallOpenButtonOpen,
        ),
      );
      handle.dispose();
    });

    testWidgets('pencere düğmeleri dokunma eylemi taşır, en az 56 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      for (final label in [Tr.fallOpenDialogCancel, Tr.fallOpenDialogConfirm]) {
        final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
        expect(tester.getSize(button).height, greaterThanOrEqualTo(56), reason: label);
        expect(tester.getSemantics(button).getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
      }
      handle.dispose();
      session.cancel(); // pencere açık kaldı: 120 sn'lik zamanlayıcıyı bırak
    });
  });
}
