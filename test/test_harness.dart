import 'package:fake_async/fake_async.dart';

import 'package:patika_app/app_state.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/settings/settings_store.dart';
import 'package:patika_app/tutorial/tutorial.dart';

import 'fakes.dart';

/// Platform eklentisi gerektirmeyen tam bir AppState: sahte TTS, konuşma
/// tanıma, titreşim, kısa ses; bellek içi ayar/cihaz/eğitim kaydı;
/// açılıştaki otomatik bağlanma kapalı.
class Harness {
  final tts = FakeSpeechOutput();
  final speech = FakeSpeechInput();
  final haptics = FakeHaptics();
  final earcons = FakeEarcons();
  final tutorialProgress = MemoryTutorialProgress(true);
  final SettingsStore settings;
  bool micGranted = true;
  late final AppState app;

  Harness({Settings initial = const Settings()})
      : settings = SettingsStore(MemorySettingsPersistence()) {
    settings.update(initial);
    app = AppState(
      autoStart: false,
      speech: tts,
      speechInput: speech,
      haptics: haptics,
      earcons: earcons,
      settings: settings,
      deviceMemory: (_) => MemoryDeviceMemory(),
      ensureMicPermission: () async => micGranted,
      tutorialProgress: tutorialProgress,
    );
  }

  /// Sıradaki tüm duyuruları "konuşulmuş" sayar (TTS bitti).
  void speakAll(FakeAsync async, {int max = 20}) {
    for (var i = 0; i < max; i++) {
      async.flushMicrotasks();
      tts.finishCurrent();
    }
    async.flushMicrotasks();
  }

  void dispose() => app.dispose();
}
