import 'package:flutter/foundation.dart';

/// Açık moda geçişte, uyarıdan ÖNCE denetlenen kapılar (Faz 7c-2, plan §1a).
/// Sırayla bakılır; ilk tutmayan kapı nedeni olarak döner (söylenecek metin
/// `Tr`'de, hem düğme hem sesli komut aynı metni kullanır).
enum FallOpenBlock {
  /// `play` derlemesi: acil mesaj gönderilemediği için açık mod anlamsız.
  unsupportedBuild,

  /// Kayıtlı acil kişi yok.
  noContacts,

  /// SMS izni verilmemiş (acil durumda izin istenmez, bkz. kurulum akışı).
  noSmsPermission,

  /// Gölge modu yeterince uzun süredir kesintisiz çalışmıyor.
  shadowTooShort,
}

class FallOpenGateResult {
  /// Engel; null ise açık mod açılabilir.
  final FallOpenBlock? block;

  /// [FallOpenBlock.shadowTooShort] için: kalan tam gün (en az 1).
  final int? daysLeft;

  /// 7 gün kapısı bu sonuçta **atlandı** (yalnızca debug; bkz.
  /// [ShadowGatePolicy]). Arayüz bunu görünür bir notla gösterir.
  final bool shadowGateBypassed;

  const FallOpenGateResult({this.block, this.daysLeft, this.shadowGateBypassed = false});

  bool get open => block == null;
}

/// 7 günlük gölge şartının atlanması. **Yalnızca release dışında** ve yalnızca
/// açıkça istenince (`--dart-define=PATIKA_FALL_SKIP_SHADOW_GATE=true`); release
/// derlemesinde ne dart-define ne kurucu parametresi işe yarar (112 test
/// numarasıyla aynı desen, bkz. `EmergencyNumber`). Uçtan uca denemeyi bir hafta
/// beklemeden yapabilmek içindir; gerçek kullanıcıya hiç ulaşmaz.
class ShadowGatePolicy {
  static const minDays = 7;

  static const _skipDefine = bool.fromEnvironment('PATIKA_FALL_SKIP_SHADOW_GATE');

  final bool _skip;

  const ShadowGatePolicy({bool debugSkip = false}) : _skip = !kReleaseMode && debugSkip;

  const ShadowGatePolicy.fromDefines() : this(debugSkip: _skipDefine);

  /// Release'te her zaman false.
  bool get skips => _skip;
}

/// Açık mod kapıları. Saf mantık: bağımlılıklar işlev olarak verilir, testte
/// sahteleri geçirilir.
class FallOpenModeGate {
  final Future<bool> Function() _directBuild;
  final Future<int> Function() _contactCount;
  final Future<bool> Function() _hasSmsPermission;
  final Future<DateTime?> Function() _shadowSince;
  final DateTime Function() _now;
  final ShadowGatePolicy _policy;

  FallOpenModeGate({
    required Future<bool> Function() directBuild,
    required Future<int> Function() contactCount,
    required Future<bool> Function() hasSmsPermission,
    required Future<DateTime?> Function() shadowSince,
    ShadowGatePolicy policy = const ShadowGatePolicy.fromDefines(),
    DateTime Function()? now,
  })  : _directBuild = directBuild,
        _contactCount = contactCount,
        _hasSmsPermission = hasSmsPermission,
        _shadowSince = shadowSince,
        _policy = policy,
        _now = now ?? DateTime.now;

  Future<FallOpenGateResult> check() async {
    if (!await _directBuild()) {
      return const FallOpenGateResult(block: FallOpenBlock.unsupportedBuild);
    }
    if (await _contactCount() < 1) {
      return const FallOpenGateResult(block: FallOpenBlock.noContacts);
    }
    if (!await _hasSmsPermission()) {
      return const FallOpenGateResult(block: FallOpenBlock.noSmsPermission);
    }

    final since = await _shadowSince();
    final required = const Duration(days: ShadowGatePolicy.minDays);
    final elapsed = since == null ? Duration.zero : _now().difference(since);
    if (elapsed >= required) return const FallOpenGateResult();

    if (_policy.skips) {
      debugPrint('[Düşme] ${ShadowGatePolicy.minDays} gün kapısı atlandı (yalnızca debug)');
      return const FallOpenGateResult(shadowGateBypassed: true);
    }
    final left = required - elapsed;
    final days = (left.inHours / 24).ceil().clamp(1, ShadowGatePolicy.minDays);
    return FallOpenGateResult(block: FallOpenBlock.shadowTooShort, daysLeft: days);
  }
}
