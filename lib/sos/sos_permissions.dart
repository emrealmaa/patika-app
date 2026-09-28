import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sos_delivery.dart';

/// Gerçek izin yoklaması. Acil durumda izin PENCERESİ açılmaz: izinler acil
/// kişi kurulumunda (Faz 7a-3) sesli açıklamayla istenir, burada yalnızca
/// durumları okunur.
class PermissionHandlerSosPermissions implements SosPermissions {
  const PermissionHandlerSosPermissions();

  @override
  Future<bool> hasSms() => _granted(Permission.sms);

  @override
  Future<bool> hasCall() => _granted(Permission.phone);

  static Future<bool> _granted(Permission permission) async {
    try {
      return await permission.isGranted;
    } catch (e) {
      debugPrint('[SOS] izin durumu okunamadı: ${e.runtimeType}');
      return false;
    }
  }
}
