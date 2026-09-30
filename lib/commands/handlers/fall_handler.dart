import 'dart:async';

import '../../fall/fall_enable_session.dart';
import '../../fall/fall_mode.dart';
import '../../l10n/strings_tr.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/fall_enable_flow.dart';
import '../action_result.dart';

/// DÜŞME niyeti (Faz 7c-2). Entity (sınıflandırıcı üretir):
/// - "ac": açık modu açar. **Her zaman iki adımlı sesli diyalog**
///   ([FallEnableFlow]); bu handler modu kendisi asla `on` yapmaz.
/// - "kapat" / "golge_kapat": düşme algılamayı tamamen kapatır (tek adım;
///   açıksa açık mod da kapanır). Kapalıyken zararsız bilgi.
/// - "golge_ac": gölge modunu açar (açarken gölge uyarısı okunur); zaten
///   açıksa bilgi verir, açık moddayken açık modu DEĞİŞTİRMEZ.
/// - "durum": mevcut modu söyler.
///
/// Bağımlılıkların hepsi verilmediyse (henüz bağlanmadıysa) komut "şu an
/// kullanılamıyor" der ve hiçbir şeyi değiştirmez.
class FallHandler {
  final FallEnableSession? _session;
  final DialogManager? _dialogs;
  final FallMode Function()? _mode;
  final Future<void> Function(FallMode mode)? _setMode;

  FallHandler({
    FallEnableSession? session,
    DialogManager? dialogs,
    FallMode Function()? mode,
    Future<void> Function(FallMode mode)? setMode,
  })  : _session = session,
        _dialogs = dialogs,
        _mode = mode,
        _setMode = setMode;

  Future<ActionResult> handle(String? entity) async {
    final session = _session;
    final dialogs = _dialogs;
    final mode = _mode;
    final setMode = _setMode;
    if (session == null || dialogs == null || mode == null || setMode == null) {
      return ActionResult.fail(Tr.fallCommandUnavailable);
    }

    switch (entity) {
      case 'ac':
        // Diyalog dakikalar sürebilir; router'ı bekletmiyoruz. Sonucu diyalog
        // bitince AppState kaydedip duyuruyor (ARA/MESAJ/acil kişi ile aynı desen).
        unawaited(dialogs.start(FallEnableFlow(session)));
        return ActionResult.handedOff('Düşme algılama açma diyaloğu başladı');
      case 'kapat':
      case 'golge_kapat':
        session.cancel();
        if (mode() == FallMode.off) return ActionResult.ok(Tr.fallOffAlready);
        await setMode(FallMode.off);
        return ActionResult.ok(Tr.fallShadowDisabled);
      case 'golge_ac':
        switch (mode()) {
          case FallMode.off:
            await setMode(FallMode.shadow);
            return ActionResult.ok(Tr.fallShadowWarning);
          case FallMode.shadow:
            return ActionResult.ok(Tr.fallShadowAlready);
          case FallMode.on:
            return ActionResult.ok(Tr.fallShadowWhileOpen);
        }
      case 'durum':
        return ActionResult.ok(switch (mode()) {
          FallMode.off => Tr.statusFallOff,
          FallMode.shadow => Tr.statusFallShadow,
          FallMode.on => Tr.statusFallOn,
        });
      default:
        return ActionResult.fail(Tr.unknownCommand);
    }
  }
}
