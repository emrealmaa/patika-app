import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın lisans listesindeki (`showLicensePage`) paket adı.
const fontLicensePackage = 'Plus Jakarta Sans';

/// Gömülü yazı tipinin OFL lisansını Flutter'ın lisans listesine ekler.
/// Font dosyalarının içinde de telif ve lisans alanı var; bu, lisansın
/// uygulamada okunabilir biçimde de bulunması için. Metin
/// `assets/fonts/OFL.txt`'ten tembel okunur (yalnızca liste açılınca).
void registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const [fontLicensePackage], text);
  });
}
