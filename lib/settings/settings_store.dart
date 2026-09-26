import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// Ayarları tek bir JSON değeri olarak saklayan katman. Arayüz sayesinde
/// testlerde plugin gerektirmeyen [MemorySettingsPersistence] kullanılıyor.
abstract class SettingsPersistence {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPrefsSettingsPersistence implements SettingsPersistence {
  static const _key = 'patika.settings.v1';
  // İlk kullanımda oluşturuluyor: plugin yokken (testler) yapıcı hata
  // fırlatıyor, bu da SettingsStore.load() içindeki try'da yakalanıyor.
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read() => _prefs.getString(_key);

  @override
  Future<void> write(String value) => _prefs.setString(_key, value);
}

class MemorySettingsPersistence implements SettingsPersistence {
  String? value;

  MemorySettingsPersistence([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// Uygulamanın tek ayar kaynağı. Değişiklikler dinleyicilere (TTS hızı,
/// dinleme süresi, ayar ekranı) anında yansır ve arka planda kaydedilir.
class SettingsStore extends ChangeNotifier {
  final SettingsPersistence _persistence;
  Settings _value = const Settings();

  SettingsStore([SettingsPersistence? persistence])
      : _persistence = persistence ?? SharedPrefsSettingsPersistence();

  Settings get value => _value;

  /// Kayıt okunamazsa (plugin yok, bozuk JSON) varsayılanlarla devam eder.
  Future<void> load() async {
    try {
      final raw = await _persistence.read();
      if (raw == null) return;
      _value = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] okunamadı, varsayılanlar kullanılıyor: $e');
    }
  }

  Future<void> update(Settings next) async {
    if (next == _value) return;
    _value = next;
    notifyListeners();
    try {
      await _persistence.write(jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('[Settings] kaydedilemedi: $e');
    }
  }
}
