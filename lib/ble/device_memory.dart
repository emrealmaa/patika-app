import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Son bağlanılan gözlüğün kimliğini hatırlar - açılışta taramadan doğrudan
/// ona bağlanmak için. Simülasyon ve gerçek mod ayrı anahtarlar kullanıyor;
/// yoksa gerçek moda geçince simülasyondaki sahte cihaza bağlanılmaya
/// çalışılırdı.
abstract class DeviceMemory {
  Future<String?> read();
  Future<void> write(String deviceId);
}

class SharedPrefsDeviceMemory implements DeviceMemory {
  final String _key;
  // İlk kullanımda oluşturuluyor (plugin yokken yapıcı hata fırlatıyor).
  late final _prefs = SharedPreferencesAsync();

  SharedPrefsDeviceMemory({required bool simulated})
      : _key = 'patika.lastDevice.${simulated ? "sim" : "real"}';

  @override
  Future<String?> read() async {
    try {
      return await _prefs.getString(_key);
    } catch (e) {
      debugPrint('[DeviceMemory] okunamadı: $e');
      return null;
    }
  }

  @override
  Future<void> write(String deviceId) async {
    try {
      await _prefs.setString(_key, deviceId);
    } catch (e) {
      debugPrint('[DeviceMemory] yazılamadı: $e');
    }
  }
}

class MemoryDeviceMemory implements DeviceMemory {
  String? value;

  MemoryDeviceMemory([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String deviceId) async => value = deviceId;
}
