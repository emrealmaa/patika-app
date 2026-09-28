import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/strings_tr.dart';
import 'permission_explainer.dart';

/// Konum izni (yalnızca "uygulama kullanılırken"; `ACCESS_BACKGROUND_LOCATION`
/// istenmez - bkz. CLAUDE.md Faz 6 kararları, madde 3). Testlerde sahtesi
/// kullanılır.
abstract class LocationAccess {
  Future<bool> isGranted();

  /// Önce nedeni sesle söyler, sonra sistem penceresini açar
  /// ([PermissionExplainer]). Verildiyse true.
  Future<bool> requestWithExplanation();
}

class PermissionLocationAccess implements LocationAccess {
  final PermissionExplainer _explainer;

  /// İzin ilk kez alındığında: arka plan servisi konum türüyle yeniden
  /// başlatılsın diye (uygulama o an ön plandadır).
  final VoidCallback? onGranted;

  PermissionLocationAccess(this._explainer, {this.onGranted});

  @override
  Future<bool> isGranted() async {
    try {
      return await Permission.locationWhenInUse.isGranted;
    } catch (e) {
      debugPrint('[Location] izin durumu okunamadı: $e');
      return false;
    }
  }

  @override
  Future<bool> requestWithExplanation() async {
    final granted = await _explainer.ensure(Permission.locationWhenInUse, Tr.locationPermissionWhy);
    if (granted) onGranted?.call();
    return granted;
  }
}
