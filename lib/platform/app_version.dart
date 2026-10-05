import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/strings_tr.dart';

/// Ayarlar ekranındaki sürüm satırının metni. Arayüz sayesinde testlerde
/// plugin gerektirmeyen [FixedAppVersion] kullanılıyor.
abstract class AppVersionSource {
  Future<String> label();
}

class PackageInfoAppVersion implements AppVersionSource {
  @override
  Future<String> label() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return Tr.versionLine(info.version, info.buildNumber);
    } catch (_) {
      return Tr.versionUnknown;
    }
  }
}

class FixedAppVersion implements AppVersionSource {
  final String text;

  const FixedAppVersion([this.text = 'Sürüm 1.0.0 (1)']);

  @override
  Future<String> label() async => text;
}
