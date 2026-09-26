import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/app_state.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/settings/settings_store.dart';

import 'fakes.dart';

/// Platform eklentisi gerektirmeyen AppState: sahte TTS/titreşim/kısa ses,
/// bellek içi ayar/cihaz kaydı, açılıştaki otomatik bağlanma kapalı.
PatikaApp testApp({FakeSpeechOutput? tts}) => PatikaApp(
      appStateFactory: () => AppState(
        autoStart: false,
        speech: tts ?? FakeSpeechOutput(),
        haptics: FakeHaptics(),
        earcons: FakeEarcons(),
        settings: SettingsStore(MemorySettingsPersistence()),
        deviceMemory: (_) => MemoryDeviceMemory(),
      ),
    );

void main() {
  testWidgets('Uygulama açılır, üç sekme görünür', (WidgetTester tester) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    expect(find.text('Bağlantı'), findsOneWidget);
    expect(find.text('Test Modu'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(find.text('Simülasyon modu'), findsOneWidget);
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

  testWidgets('Gözlük butonu simülasyonu olayı gösterir ve duyurur',
      (WidgetTester tester) async {
    // Gerçek telefon boyutu (varsayılan 800x600 test yüzeyinde butonlar
    // gezinme çubuğunun arkasına düşüyor).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final tts = FakeSpeechOutput();
    await tester.pumpWidget(testApp(tts: tts));
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();

    final tapButton = find.text('Tek dokunuş');
    await tester.scrollUntilVisible(tapButton, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(tapButton);
    await tester.pumpAndSettle();
    await tester.tap(tapButton);
    await tester.pumpAndSettle();

    expect(find.text('Gözlük: Tek dokunuş'), findsOneWidget);
    expect(tts.spoken, contains('Gözlük: Tek dokunuş'));
  });
}
