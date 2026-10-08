import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/speech_output.dart';
import 'package:patika_app/app_state.dart';
import 'package:patika_app/battery/phone_battery.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/main.dart';
import 'package:patika_app/navigation/app_identity.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/platform/location_service.dart';
import 'package:patika_app/settings/test_mode_access.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/tutorial/tutorial.dart';
import 'package:patika_app/voice/speech_input_service.dart';

/// iOS simülatöründe GERÇEK eklentilerle (TTS, rehber, konum, izinler)
/// uygulamanın ne kadarının çalıştığını yoklar. Gözlük simülasyonda; gerçek
/// arama/SMS iOS'ta zaten yok (`patika/direct` kanalı yalnızca Android).
///
/// Çalıştırmadan önce simülatörde:
///   xcrun simctl privacy CIHAZ grant contacts com.patika.patikaApp
///   xcrun simctl privacy CIHAZ grant microphone com.patika.patikaApp
///   xcrun simctl privacy CIHAZ grant location com.patika.patikaApp
///   xcrun simctl location CIHAZ set 41.0082,28.9784
///   rehbere "Ayşe Deneme" (0555 000 00 03) eklenmiş olmalı
///
/// Başarısız bir test = iOS'ta henüz eksik bir parça (yapılacaklar listesi).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('açılış: sekmeler ve Test Modu çizilir', (tester) async {
    await _launch(tester);
    expect(find.text(Tr.tabListen), findsWidgets);
    expect(find.text(Tr.tabConnection), findsWidgets);
    expect(find.text(Tr.tabSettings), findsWidgets);
    expect(find.text(Tr.tabTestMode), findsWidgets);
  });

  testWidgets('TTS: Türkçe ses var, duyuru motora gider', (tester) async {
    final (app, speech) = await _launch(tester);
    final available = await FlutterTts().isLanguageAvailable('tr-TR');
    expect(available, isTrue, reason: 'iOS\'ta tr-TR sesi yok');
    app.feedback.say('Patika iOS denemesi', dedupe: false);
    await _waitFor(tester, () => speech.spoken.contains('Patika iOS denemesi'));
    expect(speech.spoken, contains('Patika iOS denemesi'));
  });

  testWidgets('simüle gözlük bağlanır, pil gelir', (tester) async {
    final (app, speech) = await _launch(tester);
    app.connect('SIM-ESP32-S3-0001');
    await _waitFor(tester, () => app.isHealthy && app.glassesBattery != null);
    expect(app.isHealthy, isTrue);
    expect(app.glassesBattery, 80);
    expect(speech.spoken, contains(Tr.glassesConnected));
  });

  testWidgets('SAAT ve DURUM komutları yanıtlanır', (tester) async {
    final (app, _) = await _launch(tester);
    app.injectTestCommand('SAAT');
    await _waitFor(tester, () => _logged(app, PatikaIntent.saat));
    app.injectTestCommand('DURUM');
    await _waitFor(tester, () => _logged(app, PatikaIntent.durum));
    for (final intent in [PatikaIntent.saat, PatikaIntent.durum]) {
      final entry = app.log.where((e) => e.intent == intent).firstOrNull;
      expect(entry?.result.success, isTrue, reason: '$intent yanıtlanmadı');
    }
    // Simülatörde UIDevice pili hep -1; bilgi amaçlı, test sonucu değil.
    await app.pollPhoneBattery();
    debugPrint('[iOS] telefon pili: ${app.phoneBatteryPercent}');
  });

  // Bilgi amaçlı: flutter test uygulamayı her çalıştırmada yeniden kurduğu
  // için simctl ile önceden verilen izinler silinir.
  testWidgets('iOS kanalları: kimlik, pil, acil kişi deposu', (tester) async {
    final identity = await MethodChannelAppIdentity().read();
    expect(identity?.ios, isTrue);
    expect(identity?.package, 'com.patika.patikaApp');

    // Simülatörde UIDevice pili okunamayabilir (null = "bilinmiyor"); kanal
    // bağlı değilse MissingPluginException da null döner, o yüzden yalnızca
    // bilgi amaçlı.
    final battery = await MethodChannelPhoneBattery().read();
    debugPrint('[iOS] pil: ${battery?.percent} şarjda: ${battery?.charging}');

    final store = SecureFileEmergencyContactStore();
    final before = await store.readAll();
    const contact = EmergencyContact('Deneme Kişi', '0555 000 00 09');
    expect(await store.add(contact), EmergencyAddResult.added);
    expect((await SecureFileEmergencyContactStore().readAll()).map((c) => c.name),
        contains('Deneme Kişi'), reason: 'yazılan liste yeni bir depodan okunmalı');
    expect(await store.remove(contact.key), isTrue);
    expect((await store.readAll()).length, before.length);

    // Arama yokken 0 (MODE_NORMAL); kanal yoksa MissingPluginException fırlar.
    expect(await const MethodChannel('patika/audiomode').invokeMethod<int>('mode'), 0);
    // Bekleyen başlatma talimatı yok (Siri/Eylem Düğmesi tetiklenmedi).
    expect(await const MethodChannel('patika/launch').invokeMethod<String>('consumePendingAction'),
        isNull);
  });

  testWidgets('izin durumları (permission_handler) raporlanır', (tester) async {
    final statuses = {
      'mikrofon': await ph.Permission.microphone.status,
      'konuşma tanıma': await ph.Permission.speech.status,
      'rehber': await ph.Permission.contacts.status,
      'konum': await ph.Permission.locationWhenInUse.status,
      'bildirim': await ph.Permission.notification.status,
    };
    debugPrint('[iOS] izinler: $statuses');
  });

  testWidgets('rehber: flutter_contacts kişiyi okur', (tester) async {
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
    expect(contacts.map((c) => c.displayName), contains('Ayşe Deneme'));
  });

  testWidgets('ARA: uygulama rehberden kişiyi bulur', (tester) async {
    final (app, speech) = await _launch(tester);
    app.injectTestCommand('ARA', entity: 'Ayşe');
    await _waitFor(tester, () => speech.spoken.any((s) => s.contains('Ayşe Deneme')));
    app.dialogs.cancel(null);
    expect(speech.spoken.any((s) => s.contains('Ayşe Deneme')), isTrue,
        reason: 'Söylenenler: ${speech.spoken}');
  });

  testWidgets('konum: geolocator simülatör konumunu verir', (tester) async {
    final location = GeolocatorLocationService();
    final fix = await location.currentPosition();
    location.dispose();
    expect(fix, isNotNull, reason: 'Info.plist konum açıklaması / izin');
    expect(fix!.position.lat, closeTo(41.0082, 0.01));
  });

  testWidgets('SOS: iOS\'ta "gönderilemiyor" der, gönderim yolu kapalı', (tester) async {
    final (app, speech) = await _launch(tester);
    expect(await MethodChannelDirectActions().isAvailable(), isFalse);
    app.simulator!.injectButton(GlassesButton.longPress);
    await _waitFor(tester, () => speech.spoken.contains(Tr.sosUnsupported));
    expect(speech.spoken, contains(Tr.sosUnsupported));
  });

  // Konuşma tanıma izni simctl ile verilemiyor: izin yoksa sistem penceresi
  // dokunulmadan beklerdi. Simülatörde bir kez elle izin verilince çalışır.
  testWidgets('konuşma tanıma (speech_to_text) başlatılır', (tester) async {
    if (!await ph.Permission.speech.isGranted) {
      markTestSkipped('Konuşma tanıma izni yok (simctl veremiyor; elle verin)');
      return;
    }
    final ok = await SpeechInputService()
        .init()
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
    expect(ok, isTrue);
  });
}

/// Gerçek TTS'e giden her cümleyi kaydeder.
class _RecordingSpeech implements SpeechOutput {
  final _inner = FlutterTtsOutput();
  final spoken = <String>[];

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return _inner.speak(text);
  }

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> configure({required double rate, required double pitch}) =>
      _inner.configure(rate: rate, pitch: pitch);
}

class _SilentEarcons implements EarconPlayer {
  @override
  Future<void> play(Earcon earcon) async {}
}

/// Uygulamayı gerçek eklentilerle açar: simüle gözlük, Test Modu açık,
/// eğitim bitmiş, açılıştaki izin/servis adımı kapalı (sistem penceresi
/// testi bekletmesin).
Future<(AppState, _RecordingSpeech)> _launch(WidgetTester tester) async {
  final speech = _RecordingSpeech();
  late AppState app;
  await tester.pumpWidget(PatikaApp(
    appStateFactory: () => app = AppState(
      speech: speech,
      // audioplayers oynatıcıları ağaç kalktıktan sonra da çerçeve ister ve
      // sonraki testi düşürür; kısa sesler cihazda ayrıca denenecek.
      earcons: _SilentEarcons(),
      tutorialProgress: MemoryTutorialProgress(true),
      autoStart: false,
      simulated: true,
    ),
    testModeFactory: () => TestModeAccess(store: MemoryTestModeStore(unlocked: true)),
  ));
  await tester.pump();
  return (app, speech);
}

bool _logged(AppState app, PatikaIntent intent) => app.log.any((e) => e.intent == intent);

Future<void> _waitFor(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}
