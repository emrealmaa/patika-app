import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/app_state.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/platform/app_version.dart';
import 'package:patika_app/settings/settings_store.dart';
import 'package:patika_app/settings/test_mode_access.dart';
import 'package:patika_app/tutorial/tutorial.dart';

import 'fakes.dart';

/// Platform eklentisi gerektirmeyen AppState: sahte TTS/konuşma tanıma/
/// titreşim/kısa ses, bellek içi kayıtlar, açılıştaki otomatik bağlanma kapalı.
///
/// Test Modu sekmesi varsayılan olarak GİZLİ (gerçek kullanıcı gibi);
/// [testModeUnlocked] true ise açık gelir (açılışta "Test modu açık" denir).
/// [onAppCreated] AppState kurulur kurulmaz (açılış hatırlatmasından önce)
/// çağrılır: kuyrukta önceden duyuru olan açılışı taklit etmek için.
PatikaApp testApp({
  FakeSpeechOutput? tts,
  FakeSpeechInput? speech,
  bool testModeUnlocked = false,
  TestModeStore? testModeStore,
  void Function(AppState app)? onAppCreated,
}) =>
    PatikaApp(
      appVersion: const FixedAppVersion(),
      testModeFactory: () => TestModeAccess(
        store: testModeStore ?? MemoryTestModeStore(unlocked: testModeUnlocked),
      ),
      appStateFactory: () {
        final app = AppState(
          autoStart: false,
          speech: tts ?? FakeSpeechOutput(),
          speechInput: speech ?? FakeSpeechInput(),
          ensureMicPermission: () async => true,
          haptics: FakeHaptics(),
          earcons: FakeEarcons(),
          settings: SettingsStore(MemorySettingsPersistence()),
          deviceMemory: (_) => MemoryDeviceMemory(),
          tutorialProgress: MemoryTutorialProgress(true),
        );
        onAppCreated?.call(app);
        return app;
      },
    );

/// Gerçek telefon boyutu (varsayılan 800x600 test yüzeyinde butonlar
/// gezinme çubuğunun arkasına düşüyor).
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Uygulama "Konuş" sekmesiyle açılır, üç sekme görünür (Test Modu gizli)',
      (WidgetTester tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    for (final tab in ['Konuş', 'Bağlantı', 'Ayarlar']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(find.text('Test Modu'), findsNothing);
    expect(find.bySemanticsLabel('Sesli komut ver. Dokunun ve komutunuzu söyleyin.'),
        findsOneWidget);

    await tester.tap(find.text('Bağlantı'));
    await tester.pumpAndSettle();
    // Simülasyon anahtarı sıradan kullanıcıya görünmez (yalnızca Test Modu'nda).
    expect(find.text('Simülasyon modu'), findsNothing);
  });

  testWidgets('Test Modu açıkken dört sekme, Test Modu en sonda; simülasyon anahtarı orada',
      (WidgetTester tester) async {
    await tester.pumpWidget(testApp(testModeUnlocked: true));
    await tester.pump();

    for (final tab in ['Konuş', 'Bağlantı', 'Ayarlar', 'Test Modu']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();
    expect(find.text('Simülasyon modu'), findsOneWidget);
  });

  testWidgets('TalkBack açıkken "Konuş" ekranının tamamı tek buton',
      (WidgetTester tester) async {
    usePhoneSize(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(testApp());
    await tester.pump();

    final button = tester.getRect(find.byType(ElevatedButton));
    final body = tester.getRect(find.byType(Scaffold));
    // Gövdenin (uygulama çubuğu ve sekmeler hariç) neredeyse tamamı.
    expect(button.height, greaterThan(body.height * 0.7));
    expect(button.width, greaterThan(body.width * 0.9));
    expect(find.text('Gözlük bağlı değil'), findsNothing,
        reason: 'TalkBack kipinde başka öğe yok, doğrudan butona odaklanılır');
  });

  testWidgets('Konuş butonuna dokununca dinleme başlar ve durum değişir',
      (WidgetTester tester) async {
    final speech = FakeSpeechInput();
    await tester.pumpWidget(testApp(speech: speech));
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(speech.listening, isTrue);
    expect(find.bySemanticsLabel('Dinleniyor. Durdurmak için dokunun.'), findsOneWidget);
  });

  testWidgets('Test modunda kişisiz ARA gönderilince arama diyaloğu başlar',
      (WidgetTester tester) async {
    final tts = FakeSpeechOutput();
    await tester.pumpWidget(testApp(tts: tts, testModeUnlocked: true));
    await tester.pump();
    // Açılış hatırlatması bitsin: diyalog sorusu onun arkasında beklemesin.
    expect(tts.spoken, ['Test modu açık']);
    tts.finishCurrent();
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();

    // Varsayılan seçili niyet ARA, entity boş: komut router'a ulaşıp
    // diyaloğa devredildi, diyalog kimi arayacağını soruyor.
    // Test Modu ekranı uzun: düğme ekran dışında olabilir.
    final send = find.text('Komutu gönder');
    await tester.scrollUntilVisible(send, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(tts.spoken, contains('Kimi arayayım?'));
  });

  // Koruma testi: bir butonu dışarıdan Semantics(excludeSemantics: true) ile
  // sarmak dokunma eylemini siliyordu - TalkBack butonu okuyor ama çift
  // dokunuş hiçbir şey yapmıyordu ("Bağlan" butonu dahil, emülatörde
  // bulundu). Her sekmedeki her etkin buton TalkBack'ten tetiklenebilmeli.
  testWidgets('Her etkin butonun erişilebilirlik düğümünde dokunma eylemi var',
      (WidgetTester tester) async {
    // Tüm içerik ekran dışına taşmadan oluşturulsun (liste tembel kurar).
    tester.view.physicalSize = const Size(1080, 16000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(testApp(testModeUnlocked: true));
    await tester.pump();

    Future<void> expectAllButtonsTappable(String tab) async {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      if (tab == 'Bağlantı') {
        // "Bağlan" butonu olan cihaz kartı görünsün.
        await tester.tap(find.text('Tara'));
        await tester.pump(const Duration(seconds: 1));
      }
      final buttons = tester
          .widgetList<ButtonStyleButton>(find.bySubtype<ButtonStyleButton>())
          .where((b) => b.onPressed != null)
          .toList();
      expect(buttons, isNotEmpty, reason: tab);
      for (final button in buttons) {
        final data = tester.getSemantics(find.byWidget(button)).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue,
            reason: '$tab sekmesinde "${data.label}" butonu TalkBack ile tetiklenemiyor');
      }
    }

    for (final tab in ['Konuş', 'Bağlantı', 'Ayarlar', 'Test Modu']) {
      await expectAllButtonsTappable(tab);
    }
    semantics.dispose();
  });

  testWidgets('Gözlük butonu simülasyonu dinlemeyi başlatır',
      (WidgetTester tester) async {
    usePhoneSize(tester);
    final speech = FakeSpeechInput();
    await tester.pumpWidget(testApp(speech: speech, testModeUnlocked: true));
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();

    final tapButton = find.text('Tek dokunuş');
    await tester.scrollUntilVisible(tapButton, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(tapButton);
    await tester.pumpAndSettle();
    await tester.tap(tapButton);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Gözlük: Tek dokunuş'), findsOneWidget);
    expect(speech.listening, isTrue);
  });
}
