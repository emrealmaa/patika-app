import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/handlers/settings_handler.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/settings/settings_store.dart';

void main() {
  group('Settings', () {
    test('varsayılanlar', () {
      const s = Settings();
      expect(s.speechRate, 0.5);
      expect(s.silenceTimeout, const Duration(seconds: 3));
      expect(s.verbosity, Verbosity.long);
      expect(s.feedbackMode, FeedbackMode.earconOnly, reason: 'Faz 2: "Dinliyorum" yerine kısa ses');
      expect(s.nodToListen, isFalse);
    });

    test('sınırlar dışına çıkılamaz', () {
      const s = Settings();
      expect(s.copyWith(silenceTimeoutSeconds: 0).silenceTimeoutSeconds, 1);
      expect(s.copyWith(silenceTimeoutSeconds: 9).silenceTimeoutSeconds, 6);
      expect(s.copyWith(speechRateLevel: 99).speechRateLevel, Settings.speechRates.length - 1);
      expect(s.copyWith(hapticLevel: -1).hapticLevel, 0);
    });

    test('sınırdaki sesli ayar aynı nesneyi döner (değişmedi)', () {
      final fastest = const Settings().copyWith(speechRateLevel: 4);
      expect(identical(fastest.apply(SettingAction.speechFaster), fastest), isTrue);
      expect(fastest.apply(SettingAction.speechSlower).speechRateLevel, 3);
    });

    test('JSON gidiş-dönüş', () {
      const s = Settings(
        speechRateLevel: 4,
        pitchLevel: 0,
        silenceTimeoutSeconds: 5,
        verbosity: Verbosity.short,
        hapticLevel: 1,
        feedbackMode: FeedbackMode.speech,
        nodToListen: true,
      );
      expect(Settings.fromJson(jsonDecode(jsonEncode(s.toJson()))), s);
    });

    test('bozuk/eksik JSON varsayılana düşer', () {
      final s = Settings.fromJson({'speechRateLevel': 'hızlı', 'verbosity': 'yok', 'hapticLevel': 42});
      expect(s.speechRateLevel, const Settings().speechRateLevel);
      expect(s.verbosity, const Settings().verbosity);
      expect(s.hapticLevel, Settings.hapticScales.length - 1);
    });
  });

  group('SettingsStore', () {
    test('kaydeder ve yeniden yükler', () async {
      final persistence = MemorySettingsPersistence();
      final store = SettingsStore(persistence);
      await store.update(const Settings(silenceTimeoutSeconds: 5));

      final reloaded = SettingsStore(persistence);
      await reloaded.load();
      expect(reloaded.value.silenceTimeoutSeconds, 5);
    });

    test('bozuk kayıt uygulamayı durdurmaz', () async {
      final store = SettingsStore(MemorySettingsPersistence('{bozuk'));
      await store.load();
      expect(store.value, const Settings());
    });

    test('değişiklik dinleyicilere bildirilir, aynı değer bildirilmez', () async {
      final store = SettingsStore(MemorySettingsPersistence());
      var calls = 0;
      store.addListener(() => calls++);
      await store.update(const Settings());
      await store.update(const Settings(pitchLevel: 2));
      expect(calls, 1);
    });
  });

  group('SettingsHandler (sesli ayar)', () {
    late SettingsStore store;
    late SettingsHandler handler;

    setUp(() {
      store = SettingsStore(MemorySettingsPersistence());
      handler = SettingsHandler(store);
    });

    test('daha hızlı konuş -> bir kademe artar ve yeni değer söylenir', () async {
      final r = await handler.handle(SettingAction.speechFaster.name);
      expect(r.success, isTrue);
      expect(r.message, 'Konuşma hızı: Hızlı');
      expect(store.value.speechRateLevel, 3);
    });

    test('sınırda "zaten" der', () async {
      await store.update(const Settings(speechRateLevel: 4));
      final r = await handler.handle(SettingAction.speechFaster.name);
      expect(r.message, 'Konuşma hızı zaten çok hızlı');
    });

    test('titreşimi kapat', () async {
      final r = await handler.handle(SettingAction.hapticOff.name);
      expect(r.message, 'Titreşim kapatıldı');
      expect(store.value.hapticScale, 0);
    });

    test('bilinmeyen eylem', () async {
      final r = await handler.handle('uçmak');
      expect(r.success, isFalse);
    });
  });
}
