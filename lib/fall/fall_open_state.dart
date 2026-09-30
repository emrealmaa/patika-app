import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fall_mode.dart';

/// Açık moda geçişin kalıcı durumu (Faz 7c-2). Ayarlardan AYRI tutulur
/// (`LoudMessagesNotice` gibi): "ayarları sıfırla" bunları silmez.
///
/// Okunamayan durum **güvenli yöne** düşer: tam metin yeniden okunur, gölge
/// başlangıcı bilinmiyor sayılır (kapı kapalı kalır).
abstract class FallOpenState {
  /// Açık mod uyarısının tam metni, kullanıcı "anladım, aç" dediği için daha
  /// önce tamamen duyuldu mu? Yalnızca onayda yazılır (karar 3).
  Future<bool> fullTextHeard();
  Future<void> markFullTextHeard();

  /// Gölge (ya da açık) modun KESİNTİSİZ çalışmaya başladığı an; yoksa null.
  Future<DateTime?> shadowSince();
  Future<void> setShadowSince(DateTime? at);
}

class SharedPrefsFallOpenState implements FallOpenState {
  static const _fullTextKey = 'patika.fallOpenFullTextHeard.v1';
  static const _sinceKey = 'patika.fallShadowSince.v1';
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> fullTextHeard() async {
    try {
      return await _prefs.getBool(_fullTextKey) ?? false;
    } catch (e) {
      debugPrint('[Düşme] tam metin durumu okunamadı: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<void> markFullTextHeard() async {
    try {
      await _prefs.setBool(_fullTextKey, true);
    } catch (e) {
      debugPrint('[Düşme] tam metin durumu yazılamadı: ${e.runtimeType}');
    }
  }

  @override
  Future<DateTime?> shadowSince() async {
    try {
      final ms = await _prefs.getInt(_sinceKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e) {
      debugPrint('[Düşme] gölge başlangıcı okunamadı: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> setShadowSince(DateTime? at) async {
    try {
      if (at == null) {
        await _prefs.remove(_sinceKey);
      } else {
        await _prefs.setInt(_sinceKey, at.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[Düşme] gölge başlangıcı yazılamadı: ${e.runtimeType}');
    }
  }
}

class MemoryFallOpenState implements FallOpenState {
  bool heard;
  DateTime? since;

  MemoryFallOpenState({this.heard = false, this.since});

  @override
  Future<bool> fullTextHeard() async => heard;

  @override
  Future<void> markFullTextHeard() async => heard = true;

  @override
  Future<DateTime?> shadowSince() async => since;

  @override
  Future<void> setShadowSince(DateTime? at) async => since = at;
}

/// Gölge süresini izler: mod `off`'a düşünce sıfırlanır (süre KESİNTİSİZ
/// sayılır), `shadow`/`on`'a geçişte daha önce başlamadıysa şimdi başlar.
/// `shadow` ile `on` arasındaki geçiş süreyi bozmaz.
class FallShadowTracker {
  final FallOpenState _state;
  final DateTime Function() _now;

  FallShadowTracker(this._state, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Etkin mod değiştiğinde (ve açılışta) çağrılır.
  Future<void> onModeChanged(FallMode mode) async {
    if (!mode.runsSensor) {
      if (await _state.shadowSince() != null) await _state.setShadowSince(null);
      return;
    }
    if (await _state.shadowSince() == null) await _state.setShadowSince(_now());
  }
}
