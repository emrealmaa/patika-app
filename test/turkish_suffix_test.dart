import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/l10n/turkish_suffix.dart';

void main() {
  group('ablative', () {
    test('ünlüyle biten ad: "d"', () {
      expect(ablative('Ayşe'), "Ayşe'den");
      expect(ablative('Kaya'), "Kaya'dan");
    });

    test('sert ünsüzle biten ad: "t"', () {
      expect(ablative('Ahmet'), "Ahmet'ten");
      expect(ablative('Öztürk'), "Öztürk'ten");
    });

    test('yumuşak ünsüzle biten ad: "d"', () {
      expect(ablative('Okan Varol'), "Okan Varol'dan");
    });

    test('boşluk kırpılır', () {
      expect(ablative('  Ayşe  '), "Ayşe'den");
    });
  });
}
