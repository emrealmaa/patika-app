import 'dart:async';

import 'fall_consent_store.dart';
import 'fall_mode.dart';
import 'fall_open_gate.dart';
import 'fall_open_state.dart';

/// Açık moda geçişin iki adımı hangi kanaldan yürüyor (Faz 7c-2 karar 1).
/// Sesli diyalog ve ekran penceresi yalnızca arayüzdür; kurallar burada.
enum FallEnableChannel { voice, screen }

enum FallEnableBeginKind {
  /// Bir kapı tutmadı; [FallEnableBegin.gate] nedeni taşır. Hiçbir şey açılmadı.
  blocked,

  /// Zaten açık; yapılacak bir şey yok.
  alreadyOn,

  /// Kapı denetimi sürerken iptal edildi ya da başka bir başlatma geçti;
  /// bu sonuç eskidir, uyarı okutulmaz.
  superseded,

  /// Uyarı okunmalı. Mod HENÜZ açılmadı: ikinci adım (onay) gerekir.
  prompt,
}

class FallEnableBegin {
  final FallEnableBeginKind kind;
  final FallOpenGateResult? gate;

  /// Yalnızca [FallEnableBeginKind.prompt]: uyarının TAM metni mi okunacak
  /// (ilk kez), yoksa kısa hatırlatma mı?
  final bool fullText;

  const FallEnableBegin._(this.kind, {this.gate, this.fullText = false});

  /// 7 gün kapısı bu denemede atlandı (yalnızca debug); arayüz not düşer.
  bool get gateBypassed => gate?.shadowGateBypassed ?? false;
}

enum FallEnableConfirmKind {
  /// Açık mod açıldı.
  enabled,

  /// Bekleyen bir açma yok (uyarı hiç okunmadı, iptal edildi ya da bitti).
  noPending,

  /// Onay, uyarının okunduğu kanaldan gelmedi. Bekleyen açma sürer.
  wrongChannel,

  /// 120 sn içinde onaylanmadı; açma iptal oldu, yeniden başlamak gerekir.
  expired,

  /// Onay anında bir kapı artık tutmuyor (ör. acil kişi silindi).
  blocked,

  /// Bu cihazdaki onay kaydı yazılamadı; güvenli yön: açılmadı.
  storageFailed,
}

class FallEnableConfirm {
  final FallEnableConfirmKind kind;
  final FallOpenGateResult? gate;

  const FallEnableConfirm._(this.kind, {this.gate});

  bool get gateBypassed => gate?.shadowGateBypassed ?? false;
}

/// Açık moda iki adımlı geçiş (karar 1): adım 1 kapıları denetler ve uyarıyı
/// okutur, modu AÇMAZ; adım 2 yalnızca adım 1'in yapıldığı kanaldan ve
/// [timeout] içinde gelen onayla modu açar. Kapatma tek adımdır
/// ([closeOpenMode]: açıktan gölgeye).
///
/// Sessizlik, zaman aşımı, kanal uyuşmazlığı ve kapı bozulması **asla**
/// açmaz: her belirsizlik güvenli yön olan "açılmadı"ya düşer.
class FallEnableSession {
  /// Uyarının yavaş konuşma hızında tam okunması ve kullanıcının onay
  /// vermesi için yeterince uzun (tam uyarı ~30-40 sn sürebilir).
  static const timeout = Duration(seconds: 120);

  final FallOpenModeGate _gate;
  final FallOpenState _state;
  final FallConsentStore _consent;
  final FallMode Function() _currentMode;
  final Future<void> Function(FallMode mode) _setMode;

  FallEnableChannel? _channel;
  bool _expired = false;
  Timer? _timer;

  /// Her başlatma/iptalde artar: kapı denetimi sürerken iptal edilmiş ya da
  /// yenisi başlamış bir açmanın sonucu bekleyen duruma yazılmaz.
  int _generation = 0;

  FallEnableSession({
    required FallOpenModeGate gate,
    required FallOpenState state,
    required FallConsentStore consent,
    required FallMode Function() currentMode,
    required Future<void> Function(FallMode mode) setMode,
  })  : _gate = gate,
        _state = state,
        _consent = consent,
        _currentMode = currentMode,
        _setMode = setMode;

  /// Onay bekleyen bir açma var mı?
  bool get pending => _channel != null;

  /// Bekleyen açmanın kanalı; yoksa null.
  FallEnableChannel? get pendingChannel => _channel;

  /// Adım 1: kapıları denetler; tutarsa uyarı için [FallEnableBeginKind.prompt]
  /// döner ve [channel] için bekleyen açma kurar (öncekini, hangi kanaldan
  /// olursa olsun, geçersiz kılar). Mod bu çağrıda DEĞİŞMEZ.
  Future<FallEnableBegin> begin(FallEnableChannel channel) async {
    final generation = ++_generation;
    _clear();
    _expired = false;
    if (_currentMode() == FallMode.on) {
      return const FallEnableBegin._(FallEnableBeginKind.alreadyOn);
    }
    final gate = await _gate.check();
    final fullText = !await _state.fullTextHeard();
    // Denetim sürerken iptal ya da yeni başlatma olduysa bu sonuç eskidir.
    if (generation != _generation) {
      return const FallEnableBegin._(FallEnableBeginKind.superseded);
    }
    if (!gate.open) return FallEnableBegin._(FallEnableBeginKind.blocked, gate: gate);

    _channel = channel;
    _timer = Timer(timeout, () {
      _timer = null;
      _channel = null;
      _expired = true;
    });
    return FallEnableBegin._(FallEnableBeginKind.prompt, gate: gate, fullText: fullText);
  }

  /// Adım 2: kullanıcı "anladım, aç" dedi / "Anladım, aç" düğmesine bastı.
  /// Yalnızca bekleyen açmanın kanalından kabul edilir; kapılar yeniden
  /// denetlenir. Başarıda mod açılır, tam metin bayrağı yazılır (karar 3).
  Future<FallEnableConfirm> confirm(FallEnableChannel channel) async {
    if (_expired) {
      _expired = false;
      return const FallEnableConfirm._(FallEnableConfirmKind.expired);
    }
    final pendingChannel = _channel;
    if (pendingChannel == null) return const FallEnableConfirm._(FallEnableConfirmKind.noPending);
    if (pendingChannel != channel) {
      return const FallEnableConfirm._(FallEnableConfirmKind.wrongChannel);
    }

    final generation = ++_generation;
    final gate = await _gate.check();
    if (generation != _generation || _channel != channel) {
      // Denetim sürerken iptal, yeni başlatma ya da süre dolumu oldu: açma.
      final expired = _expired;
      _expired = false;
      return FallEnableConfirm._(
          expired ? FallEnableConfirmKind.expired : FallEnableConfirmKind.noPending);
    }
    if (!gate.open) {
      _clear();
      return FallEnableConfirm._(FallEnableConfirmKind.blocked, gate: gate);
    }

    _clear();
    // Bu cihazdaki onay kaydı MOD AÇILMADAN yazılır (yedekten gelmez; bkz.
    // [FallConsentStore]). Yazılamazsa açık mod açılmaz.
    if (!await _consent.grant()) {
      return const FallEnableConfirm._(FallEnableConfirmKind.storageFailed);
    }
    await _setMode(FallMode.on);
    await _state.markFullTextHeard();
    return FallEnableConfirm._(FallEnableConfirmKind.enabled, gate: gate);
  }

  /// Bekleyen açmayı bırakır (vazgeç, diyalog iptali, ekran penceresi kapandı).
  /// Tam metin bayrağı YAZILMAZ: duyup vazgeçen bir sonraki denemede yine tam
  /// metni duyar.
  void cancel() {
    _generation++;
    _clear();
    _expired = false;
  }

  /// Kapatma: her kanalda tek adım. Açıksa gölgeye düşer (gölge sürer) ve
  /// true döner; açık değilse false. Bekleyen açma da iptal olur.
  Future<bool> closeOpenMode() async {
    cancel();
    if (_currentMode() != FallMode.on) return false;
    await _setMode(FallMode.shadow);
    return true;
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _channel = null;
  }
}
