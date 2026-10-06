import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/theme/font_license.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(LicenseRegistry.reset);

  test('yazı tipinin OFL lisansı uygulamanın lisans listesinde', () async {
    registerFontLicense();
    final entries = await LicenseRegistry.licenses.toList();
    final font = entries.where((e) => e.packages.contains(fontLicensePackage)).toList();
    expect(font, hasLength(1));
    final text = font.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Copyright 2020 The Plus Jakarta Sans Project Authors'));
    expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });
}
