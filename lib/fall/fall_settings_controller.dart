import 'package:flutter/foundation.dart';

import 'fall_enable_session.dart';
import 'fall_mode.dart';
import 'fall_open_state.dart';

/// Ayarlar ekranındaki "Düşme algılama (deneysel)" bölümünün özeti.
class FallSettingsStatus {
  final FallMode mode;

  /// Gölge (ya da açık) modun kesintisiz çalıştığı tam gün; bilinmiyorsa null.
  final int? runningDays;

  /// Gölge kaydındaki kayıt sayısı.
  final int records;

  const FallSettingsStatus({required this.mode, this.runningDays, required this.records});
}

/// Ayarlar ekranının düşme algılama bölümünün bağımlılığı (Faz 7c-2, karar 12).
/// Ekran uygulama durumunu bilmez; mod, kayıt sayısı ve iki adımlı açma
/// oturumu buradan gelir. **Modu doğrudan `on` yapan bir yol yoktur**: açma
/// yalnızca [session] ile (uyarı + onay) olur.
class FallSettingsController extends ChangeNotifier {
  final FallEnableSession session;
  final FallMode Function() _mode;
  final Future<void> Function(FallMode mode) _setMode;
  final FallOpenState _state;
  final int Function() _recordCount;
  final DateTime Function() _now;

  FallSettingsController({
    required this.session,
    required FallMode Function() mode,
    required Future<void> Function(FallMode mode) setMode,
    required FallOpenState state,
    required int Function() recordCount,
    DateTime Function()? now,
  })  : _mode = mode,
        _setMode = setMode,
        _state = state,
        _recordCount = recordCount,
        _now = now ?? DateTime.now;

  FallMode get mode => _mode();

  Future<FallSettingsStatus> status() async {
    final since = await _state.shadowSince();
    final days = since == null ? null : _now().difference(since).inDays.clamp(0, 100000);
    return FallSettingsStatus(mode: _mode(), runningDays: days, records: _recordCount());
  }

  /// Gölge anahtarı. Açmak: kapalıysa gölgeye geçer (açıksa açık mod korunur).
  /// Kapatmak: tek adım, açık mod da dahil tamamen kapanır (karar: "kapat" =
  /// off); bekleyen bir açma da iptal olur.
  Future<void> setShadowEnabled(bool enabled) async {
    session.cancel();
    if (enabled) {
      if (_mode() == FallMode.off) await _setMode(FallMode.shadow);
    } else if (_mode() != FallMode.off) {
      await _setMode(FallMode.off);
    }
    notifyListeners();
  }

  /// "Açık modu kapat": tek adım, gölgeye düşer (gölge sürer).
  Future<bool> closeOpenMode() async {
    final closed = await session.closeOpenMode();
    notifyListeners();
    return closed;
  }

  /// Mod dışarıdan değiştiğinde (sesli komut, kapı bozulması) ekranı yeniler.
  void changed() => notifyListeners();
}
