import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/app_state.dart';
import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/simulated_ble_service.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/platform/app_version.dart';
import 'package:patika_app/screens/connection_screen.dart';
import 'package:patika_app/screens/settings_screen.dart';
import 'package:patika_app/settings/test_mode_access.dart';

import 'fakes.dart';
import 'test_harness.dart';
import 'widget_test.dart' show testApp, usePhoneSize;

/// Okunabilir zaman: testlerde gerçek saat akmasın.
class _Clock {
  DateTime now = DateTime(2026, 10, 1, 9, 0, 0);

  void advance(Duration d) => now = now.add(d);
}

class _ThrowingStore implements TestModeStore {
  @override
  Future<bool> readUnlocked() async => throw StateError('okunamadı');

  @override
  Future<void> writeUnlocked(bool value) async =>
      throw StateError('yazılamadı');
}

void main() {
  group('TestModeAccess (7 dokunuş)', () {
    late _Clock clock;
    late MemoryTestModeStore store;
    late TestModeAccess access;

    setUp(() {
      clock = _Clock();
      store = MemoryTestModeStore();
      access = TestModeAccess(store: store, now: () => clock.now);
    });

    test('ilk 3 dokunuş sessiz sayar, 4-6 "N dokunuş daha" der, 7. açar', () {
      final kinds = <(TestModeTapKind, int)>[];
      for (var i = 0; i < 7; i++) {
        final t = access.tap();
        kinds.add((t.kind, t.remaining));
        clock.advance(const Duration(milliseconds: 500));
      }
      expect(kinds, [
        (TestModeTapKind.counting, 0),
        (TestModeTapKind.counting, 0),
        (TestModeTapKind.counting, 0),
        (TestModeTapKind.countdown, 3),
        (TestModeTapKind.countdown, 2),
        (TestModeTapKind.countdown, 1),
        (TestModeTapKind.unlocked, 0),
      ]);
      expect(access.unlocked, isTrue);
    });

    test('açılınca kalıcı yazılır; yeni örnek açık yüklenir', () async {
      for (var i = 0; i < 7; i++) {
        access.tap();
      }
      await Future<void>.delayed(Duration.zero);
      expect(store.unlocked, isTrue);

      final reopened = TestModeAccess(store: store, now: () => clock.now);
      expect(reopened.unlocked, isFalse, reason: 'yüklemeden önce gizli');
      await reopened.load();
      expect(reopened.unlocked, isTrue);
    });

    test(
      '3 saniyeden uzun ara sayacı sıfırlar: dağınık dokunuşlar birikmez',
      () {
        for (var i = 0; i < 6; i++) {
          access.tap();
        }
        clock.advance(
          TestModeAccess.resetAfter + const Duration(milliseconds: 1),
        );
        expect(
          access.tap().kind,
          TestModeTapKind.counting,
          reason: 'yeniden 1. dokunuş',
        );
        expect(access.unlocked, isFalse);
        // Tam 3 sn ara sıfırlamaz (sınır dahil değil).
        final a2 = TestModeAccess(
          store: MemoryTestModeStore(),
          now: () => clock.now,
        );
        for (var i = 0; i < 6; i++) {
          a2.tap();
          clock.advance(TestModeAccess.resetAfter);
        }
        expect(a2.tap().kind, TestModeTapKind.unlocked);
      },
    );

    test('açıkken dokunmak "zaten açık" der', () {
      for (var i = 0; i < 7; i++) {
        access.tap();
      }
      expect(access.tap().kind, TestModeTapKind.alreadyUnlocked);
    });

    test(
      'gizleme kalıcıdır ve yeniden açmak yeniden 7 dokunuş ister',
      () async {
        for (var i = 0; i < 7; i++) {
          access.tap();
        }
        access.hide();
        await Future<void>.delayed(Duration.zero);
        expect(access.unlocked, isFalse);
        expect(store.unlocked, isFalse);
        for (var i = 0; i < 6; i++) {
          expect(access.tap().kind, isNot(TestModeTapKind.unlocked));
        }
        expect(access.tap().kind, TestModeTapKind.unlocked);
      },
    );

    test('kayıt okunamaz/yazılamazsa çökmez ve gizli kalır', () async {
      final broken = TestModeAccess(
        store: _ThrowingStore(),
        now: () => clock.now,
      );
      await broken.load();
      expect(broken.unlocked, isFalse);
      for (var i = 0; i < 7; i++) {
        broken.tap();
      }
      expect(broken.unlocked, isTrue, reason: 'oturum boyunca açılabilir');
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('açılışta "Test modu açık" hatırlatması', () {
    test('kapalıyken hiç hatırlatmaz', () async {
      final spoken = <String>[];
      final access = TestModeAccess(store: MemoryTestModeStore());
      await access.load();
      expect(access.remindOnLaunch(spoken.add, 'x'), isFalse);
      expect(spoken, isEmpty);
    });

    test('açıkken HER açılışta hatırlatır (aynı gün de)', () async {
      final store = MemoryTestModeStore(unlocked: true);
      final spoken = <String>[];

      Future<bool> launch() async {
        final access = TestModeAccess(store: store);
        await access.load();
        return access.remindOnLaunch(spoken.add, Tr.testModeReminder);
      }

      expect(await launch(), isTrue);
      expect(await launch(), isTrue, reason: 'ikinci açılış da hatırlatır');
      expect(await launch(), isTrue);
      expect(spoken, List.filled(3, Tr.testModeReminder));
    });

    test('7 dokunuşla açıldıktan sonraki açılışta hatırlatır', () async {
      final store = MemoryTestModeStore();
      final access = TestModeAccess(store: store);
      for (var i = 0; i < 7; i++) {
        access.tap();
      }
      await Future<void>.delayed(Duration.zero);
      final restarted = TestModeAccess(store: store);
      await restarted.load();
      final spoken = <String>[];
      expect(restarted.remindOnLaunch(spoken.add, 'x'), isTrue);
      expect(spoken, ['x']);
    });

    test('gizlendikten sonraki açılışta sessiz', () async {
      final store = MemoryTestModeStore(unlocked: true);
      final access = TestModeAccess(store: store);
      await access.load();
      access.hide();
      await Future<void>.delayed(Duration.zero);
      final restarted = TestModeAccess(store: store);
      await restarted.load();
      final spoken = <String>[];
      expect(restarted.remindOnLaunch(spoken.add, 'x'), isFalse);
      expect(spoken, isEmpty);
    });
  });

  group('okunur komut adları', () {
    test('her niyetin ham adından farklı, Türkçe bir karşılığı var', () {
      for (final intent in PatikaIntent.values) {
        final label = Tr.commandName(intent.name);
        expect(
          label,
          isNot(intent.name),
          reason: '${intent.name} ham adla gösteriliyor',
        );
        expect(
          label,
          matches(RegExp(r'^\p{Lu}[\p{L} ]+$', unicode: true)),
          reason: '${intent.name}: "$label" camelCase/teknik görünüyor',
        );
      }
    });

    test('bilinmeyen ad olduğu gibi döner (çökmez)', () {
      expect(Tr.commandName('yeniNiyet'), 'yeniNiyet');
    });
  });

  group('gerçek kullanıcı açılışı (release varsayılanı)', () {
    test('release\'te simülasyon KAPALI, aksi halde açık', () {
      expect(AppState.defaultSimulated(release: true), isFalse);
      expect(AppState.defaultSimulated(release: false), isTrue);
    });

    test('simulated: false -> gerçek BLE üreticisi kullanılır, simülatör yok', () {
      var realCreated = 0;
      final h = Harness(
        simulated: false,
        // Gerçek RealBleService plugin gerektirir; üretici çağrıldı mı diye bakılır.
        realBleFactory: () {
          realCreated++;
          return SimulatedBleService();
        },
      );
      addTearDown(h.dispose);
      expect(h.app.isSimulated, isFalse);
      expect(realCreated, 1, reason: 'açılışta gerçek BLE kurulmalı');
      expect(h.app.simulator, isNull, reason: 'gerçek modda elle komut enjekte edilemez');
    });

    test('simulated: true -> gerçek BLE üreticisi HİÇ çağrılmaz', () {
      var realCreated = 0;
      final h = Harness(
        simulated: true,
        realBleFactory: () {
          realCreated++;
          return SimulatedBleService();
        },
      );
      addTearDown(h.dispose);
      expect(realCreated, 0);
    });

    test('simulated: true -> simülasyon kurulur', () {
      final h = Harness(simulated: true);
      addTearDown(h.dispose);
      expect(h.app.isSimulated, isTrue);
      expect(h.app.simulator, isNotNull);
    });

    test(
      'varsayılan (debug/test) simülasyondur: mevcut testlerin dayanağı',
      () {
        final h = Harness();
        addTearDown(h.dispose);
        expect(h.app.isSimulated, AppState.defaultSimulated());
      },
    );

    testWidgets(
      'gerçek modda Bağlantı sekmesi simülasyon anahtarı ve ham kimlik göstermez',
      (tester) async {
        usePhoneSize(tester);
        final h = Harness(simulated: false, realBleFactory: SimulatedBleService.new);
        addTearDown(h.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConnectionScreen(state: h.app)),
          ),
        );
        expect(find.text(Tr.simulationMode), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.text(Tr.scan), findsOneWidget);
      },
    );

    testWidgets(
      'bulunan cihazın ham kimliği (MAC/UUID) gösterilmez, adı gösterilir',
      (tester) async {
        usePhoneSize(tester);
        final h = Harness(simulated: true);
        addTearDown(h.dispose);
        // Simülatör taramayı 600 ms gecikmeyle bitirir: sahte zamanı ilerlet
        // (await ile beklemek testi sonsuza dek takar).
        unawaited(h.app.startScan());
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConnectionScreen(state: h.app)),
          ),
        );
        await tester.pump();
        expect(h.app.devices, isNotEmpty);
        for (final d in h.app.devices) {
          expect(find.text(d.name), findsOneWidget);
          expect(find.text(d.id), findsNothing, reason: 'ham kimlik sızmış');
        }
      },
    );
  });

  group('Ayarlar sürüm satırı ve gizli erişim', () {
    Future<(Harness, TestModeAccess)> pumpSettings(WidgetTester tester) async {
      usePhoneSize(tester);
      final h = Harness();
      addTearDown(h.dispose);
      final access = TestModeAccess(store: MemoryTestModeStore());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              store: h.settings,
              feedback: h.app.feedback,
              onStartTutorial: () {},
              testMode: access,
              version: const FixedAppVersion('Sürüm 2.3.4 (56)'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (h, access);
    }

    Finder versionTile() => find.text('Sürüm 2.3.4 (56)');

    testWidgets(
      'sürüm satırı görünür, en az 56 dp ve TalkBack\'te yalnızca sürümü okur',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSettings(tester);
        final tile = versionTile();
        await tester.scrollUntilVisible(
          tile,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .getSize(
                find.ancestor(of: tile, matching: find.byType(InkWell)).first,
              )
              .height,
          greaterThanOrEqualTo(56),
        );
        final data = tester.getSemantics(tile).getSemanticsData();
        expect(data.label, 'Sürüm 2.3.4 (56)');
        expect(
          data.hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'TalkBack çift dokunuşu iletilebilmeli',
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'her dokunuşta kısa titreşim; 4. dokunuştan itibaren sesli sayaç; 7.\'de açılış',
      (tester) async {
        final (h, access) = await pumpSettings(tester);
        final tile = versionTile();
        await tester.scrollUntilVisible(
          tile,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        int ticks() => h.haptics.played
            .where((p) => p.$1 == HapticPatternId.listening)
            .length;

        for (var i = 1; i <= 3; i++) {
          await tester.tap(tile);
          await tester.pump();
        }
        expect(ticks(), 3);
        expect(h.tts.spoken, isEmpty, reason: 'ilk 3 dokunuş sessiz');

        await tester.tap(tile);
        await tester.pump();
        expect(h.tts.spoken.last, Tr.testModeTapsLeft(3));
        expect(ticks(), 4);

        await tester.tap(tile);
        await tester.pump();
        await tester.tap(tile);
        await tester.pump();
        expect(h.tts.spoken.last, Tr.testModeTapsLeft(1));
        expect(access.unlocked, isFalse);

        await tester.tap(tile);
        await tester.pump();
        expect(access.unlocked, isTrue);
        expect(h.tts.spoken.last, Tr.testModeOpened);

        await tester.tap(tile);
        await tester.pump();
        expect(h.tts.spoken.last, Tr.testModeAlreadyOpen);
      },
    );

    testWidgets(
      'testMode verilmezse satır yalnızca bilgidir, dokunmak hiçbir şey yapmaz',
      (tester) async {
        usePhoneSize(tester);
        final h = Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsScreen(
                store: h.settings,
                feedback: h.app.feedback,
                onStartTutorial: () {},
                version: const FixedAppVersion('Sürüm 2.3.4 (56)'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          versionTile(),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(versionTile());
        await tester.pump();
        expect(h.tts.spoken, isEmpty);
      },
    );
  });

  group('uygulama içinde: sekmeler ve TalkBack', () {
    /// Alt çubuktaki sekmelerin TalkBack etiketleri (soldan sağa, gezinme sırası).
    List<String> tabLabels(WidgetTester tester) {
      final labels = <String>[];
      void visit(SemanticsNode node) {
        final label = node.label;
        if (label.contains('Sekme ')) labels.add(label.replaceAll('\n', ' '));
        node.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(tester.getSemantics(find.byType(NavigationBar)));
      return labels;
    }

    testWidgets('Test Modu gizliyken üç sekme: etiketler ve sıra doğru', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      usePhoneSize(tester);
      await tester.pumpWidget(testApp());
      await tester.pump();
      final labels = tabLabels(tester);
      expect(labels, hasLength(3), reason: '$labels');
      expect(labels[0], allOf(contains('Konuş'), contains('1 / 3')));
      expect(labels[1], allOf(contains('Bağlantı'), contains('2 / 3')));
      expect(labels[2], allOf(contains('Ayarlar'), contains('3 / 3')));
      semantics.dispose();
    });

    testWidgets(
      'Test Modu açıkken dört sekme; ilk üçünün sırası değişmez, Test Modu sonda',
      (tester) async {
        final semantics = tester.ensureSemantics();
        usePhoneSize(tester);
        await tester.pumpWidget(testApp(testModeUnlocked: true));
        await tester.pump();
        final labels = tabLabels(tester);
        expect(labels, hasLength(4), reason: '$labels');
        expect(labels[0], allOf(contains('Konuş'), contains('1 / 4')));
        expect(labels[1], allOf(contains('Bağlantı'), contains('2 / 4')));
        expect(labels[2], allOf(contains('Ayarlar'), contains('3 / 4')));
        expect(labels[3], allOf(contains('Test Modu'), contains('4 / 4')));
        semantics.dispose();
      },
    );

    testWidgets(
      'Ayarlar\'da 7 dokunuş sekmeyi ekler; Test Modu\'ndan gizleyince Konuş\'a dönülür',
      (tester) async {
        usePhoneSize(tester);
        final tts = FakeSpeechOutput();
        final store = MemoryTestModeStore();
        await tester.pumpWidget(testApp(tts: tts, testModeStore: store));
        await tester.pump();
        expect(find.text('Test Modu'), findsNothing);

        await tester.tap(find.text('Ayarlar'));
        await tester.pumpAndSettle();
        final tile = find.text('Sürüm 1.0.0 (1)');
        await tester.scrollUntilVisible(
          tile,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        for (var i = 0; i < 7; i++) {
          await tester.tap(tile);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Test Modu'), findsOneWidget);
        expect(tts.spoken, contains(Tr.testModeOpened));
        expect(store.unlocked, isTrue);

        // Kullanıcı Ayarlar'da kalır: açılış odağı/sekmeyi değiştirmez.
        expect(find.text('Sürüm 1.0.0 (1)'), findsOneWidget);

        await tester.tap(find.text('Test Modu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(Tr.testModeHide));
        await tester.pumpAndSettle();
        expect(find.text('Test Modu'), findsNothing);
        expect(tts.spoken, contains(Tr.testModeHidden));
        expect(store.unlocked, isFalse);
        // Konuş ekranı (sesli komut butonu) görünür.
        expect(
          find.bySemanticsLabel(
            'Sesli komut ver. Dokunun ve komutunuzu söyleyin.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('açılışta Test Modu açıksa "Test modu açık" söylenir',
        (tester) async {
      final tts = FakeSpeechOutput();
      await tester.pumpWidget(testApp(tts: tts, testModeUnlocked: true));
      await tester.pump();
      await tester.pump();
      expect(tts.spoken, contains(Tr.testModeReminder));
    });

    testWidgets('Test Modu gizliyken hatırlatma yok', (tester) async {
      final tts = FakeSpeechOutput();
      await tester.pumpWidget(testApp(tts: tts));
      await tester.pump();
      await tester.pump();
      expect(tts.spoken, isNot(contains(Tr.testModeReminder)));
    });

    testWidgets(
      'hatırlatma low: sıradaki high duyuruyu kesmez, onun ardından gelir',
      (tester) async {
        final tts = FakeSpeechOutput();
        late AppState app;
        await tester.pumpWidget(
          testApp(
            tts: tts,
            testModeUnlocked: true,
            onAppCreated: (a) {
              app = a;
              a.feedback.say('Gözlük bağlantısı koptu',
                  priority: AnnouncementPriority.high);
            },
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tts.spoken, ['Gözlük bağlantısı koptu']);
        expect(tts.stops, 0, reason: 'hatırlatma high duyuruyu kesmemeli');

        tts.finishCurrent();
        await tester.pump();
        expect(tts.spoken, ['Gözlük bağlantısı koptu', Tr.testModeReminder]);
        expect(app.feedback.queue.current?.priority, AnnouncementPriority.low);
      },
    );

    testWidgets('hatırlatma konuşulurken gelen high duyuru onu hemen keser',
        (tester) async {
      final tts = FakeSpeechOutput();
      late AppState app;
      await tester.pumpWidget(
        testApp(tts: tts, testModeUnlocked: true, onAppCreated: (a) => app = a),
      );
      await tester.pump();
      await tester.pump();
      expect(tts.spoken, [Tr.testModeReminder]);
      expect(app.feedback.queue.current?.priority, AnnouncementPriority.low);

      app.feedback.say('Gözlük bağlantısı koptu',
          priority: AnnouncementPriority.high);
      await tester.pump();
      expect(tts.stops, 1, reason: 'hatırlatma kesilmeli');
      expect(tts.spoken.last, 'Gözlük bağlantısı koptu');
    });
  });

  group('komut geçmişi okunur adlarla', () {
    testWidgets(
      'Bağlantı sekmesinde "gecisModu" değil "Karşıya geçiş" görünür',
      (tester) async {
        usePhoneSize(tester);
        final h = Harness();
        addTearDown(h.dispose);
        await h.app.submitVoiceCommand(BleCommand.fromWire('GECIS_MODU', null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConnectionScreen(state: h.app)),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Karşıya geçiş'), findsWidgets);
        expect(find.textContaining('gecisModu'), findsNothing);
      },
    );
  });
}
