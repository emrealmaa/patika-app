import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test Modu sekmesinin gizli erişim durumunun kalıcı saklanması. Arayüz
/// sayesinde testlerde plugin gerektirmeyen [MemoryTestModeStore] kullanılıyor.
abstract class TestModeStore {
  Future<bool> readUnlocked();
  Future<void> writeUnlocked(bool value);
}

class SharedPrefsTestModeStore implements TestModeStore {
  static const _unlockedKey = 'patika.testMode.unlocked';
  // İlk kullanımda oluşturuluyor: plugin yokken (testler) yapıcı hata fırlatır.
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> readUnlocked() async =>
      await _prefs.getBool(_unlockedKey) ?? false;

  @override
  Future<void> writeUnlocked(bool value) => _prefs.setBool(_unlockedKey, value);
}

class MemoryTestModeStore implements TestModeStore {
  bool unlocked;

  MemoryTestModeStore({this.unlocked = false});

  @override
  Future<bool> readUnlocked() async => unlocked;

  @override
  Future<void> writeUnlocked(bool value) async => unlocked = value;
}

/// Bir dokunuşun sonucu: arayüz buna göre titreşir/konuşur.
enum TestModeTapKind {
  /// Sayaç ilerledi, henüz sessiz (yalnızca kısa titreşim).
  counting,

  /// Eşiğe yaklaşıldı: [TestModeTap.remaining] dokunuş kaldı denir.
  countdown,

  /// Bu dokunuşla Test Modu açıldı.
  unlocked,

  /// Zaten açıktı.
  alreadyUnlocked,
}

class TestModeTap {
  final TestModeTapKind kind;
  final int remaining;

  const TestModeTap(this.kind, [this.remaining = 0]);
}

/// Test Modu sekmesinin gizli erişimi (Android "Geliştirici seçenekleri"
/// deseni): sürüm satırına art arda [requiredTaps] kez dokunmak sekmeyi
/// açar. Debug ve release'de aynı çalışır. Durum kalıcıdır (yeniden
/// başlatınca açık kalır); kazara açık kalmasın diye açıkken her uygulama
/// açılışında sesli hatırlatma yapılır ([remindOnLaunch]).
class TestModeAccess extends ChangeNotifier {
  static const requiredTaps = 7;

  /// Bu dokunuştan itibaren "N dokunuş kaldı" denir (Android gibi).
  static const countdownFromTap = 4;

  /// Bu kadar süre dokunulmazsa sayaç sıfırlanır: dağınık dokunuşlar birikmez.
  static const resetAfter = Duration(seconds: 3);

  final TestModeStore _store;
  final DateTime Function() _now;

  bool _unlocked = false;
  int _count = 0;
  DateTime? _lastTap;

  TestModeAccess({TestModeStore? store, DateTime Function()? now})
    : _store = store ?? SharedPrefsTestModeStore(),
      _now = now ?? DateTime.now;

  bool get unlocked => _unlocked;

  /// Kayıt okunamazsa (plugin yok) kilitli kalır: gizli olan güvenli taraf.
  Future<void> load() async {
    try {
      final value = await _store.readUnlocked();
      if (value == _unlocked) return;
      _unlocked = value;
      notifyListeners();
    } catch (e) {
      debugPrint('[TestMode] okunamadı, gizli kalıyor: $e');
    }
  }

  TestModeTap tap() {
    if (_unlocked) {
      _count = 0;
      return const TestModeTap(TestModeTapKind.alreadyUnlocked);
    }
    final now = _now();
    final last = _lastTap;
    if (last != null && now.difference(last) > resetAfter) _count = 0;
    _lastTap = now;
    _count++;
    if (_count >= requiredTaps) {
      _count = 0;
      _unlocked = true;
      _persist(() => _store.writeUnlocked(true));
      notifyListeners();
      return const TestModeTap(TestModeTapKind.unlocked);
    }
    if (_count >= countdownFromTap) {
      return TestModeTap(TestModeTapKind.countdown, requiredTaps - _count);
    }
    return const TestModeTap(TestModeTapKind.counting);
  }

  /// Test Modu'nu gizler (kalıcı).
  void hide() {
    if (!_unlocked) return;
    _unlocked = false;
    _count = 0;
    _persist(() => _store.writeUnlocked(false));
    notifyListeners();
  }

  /// Uygulama açılışında çağrılır ([load]'dan sonra): açıksa [say] ile
  /// hatırlatır, kapalıysa sessiz kalır. Hatırlatıp hatırlatmadığını döner.
  bool remindOnLaunch(void Function(String text) say, String text) {
    if (!_unlocked) return false;
    say(text);
    return true;
  }

  /// Yazma hatası (ya da senkron fırlatma) arayüzü bozmasın.
  void _persist(Future<void> Function() write) {
    try {
      write().catchError((Object e) => debugPrint('[TestMode] yazılamadı: $e'));
    } catch (e) {
      debugPrint('[TestMode] yazılamadı: $e');
    }
  }
}
