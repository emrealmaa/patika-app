import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/app_state.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/settings/settings_store.dart';
import 'package:patika_app/tutorial/tutorial.dart';

import 'fakes.dart';

/// Platform eklentisi gerektirmeyen AppState: sahte TTS/konuşma tanıma/
/// titreşim/kısa ses, bellek içi kayıtlar, açılıştaki otomatik bağlanma kapalı.
PatikaApp testApp({FakeSpeechOutput? tts, FakeSpeechInput? speech}) => PatikaApp(
      appStateFactory: () => AppState(
        autoStart: false,
        speech: tts ?? FakeSpeechOutput(),
        speechInput: speech ?? FakeSpeechInput(),
        ensureMicPermission: () async => true,
        haptics: FakeHaptics(),
        earcons: FakeEarcons(),
        settings: SettingsStore(MemorySettingsPersistence()),
        deviceMemory: (_) => MemoryDeviceMemory(),
        tutorialProgress: MemoryTutorialProgress(true),
      ),
    );

/// Gerçek telefon boyutu (varsayılan 800x600 test yüzeyinde butonlar
/// gezinme çubuğunun arkasına düşüyor).
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Uygulama "Konuş" sekmesiyle açılır, dört sekme görünür',
      (WidgetTester tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    for (final tab in ['Konuş', 'Bağlantı', 'Test Modu', 'Ayarlar']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(find.bySemanticsLabel('Sesli komut ver. Dokunun ve komutunuzu söyleyin.'),
        findsOneWidget);

    await tester.tap(find.text('Bağlantı'));
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

  testWidgets('Test modunda sahte komut gönderilince log listeye eklenir',
      (WidgetTester tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Komutu gönder'));
    await tester.pumpAndSettle();

    // Varsayılan seçili niyet ARA, entity boş bırakıldığı için handler
    // "Kimi arayacağımı anlayamadım" ile başarısız sonuç döner - komutun
    // gerçekten router'a ulaşıp işlendiğinin kanıtı bu log satırı. Geçmiş,
    // test bölümlerinin altında - görünene kadar kaydırılıyor.
    final logLine = find.textContaining('Kimi arayacağımı anlayamadım');
    await tester.scrollUntilVisible(logLine, 300,
        scrollable: find.byType(Scrollable).first);
    expect(logLine, findsOneWidget);
  });

  testWidgets('Gözlük butonu simülasyonu dinlemeyi başlatır',
      (WidgetTester tester) async {
    usePhoneSize(tester);
    final speech = FakeSpeechInput();
    await tester.pumpWidget(testApp(speech: speech));
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
