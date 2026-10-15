import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/accessibility/speech_output.dart';

void main() {
  group('pickBestVoice', () {
    test('premium > enhanced > default', () {
      final voices = [
        {'name': 'Yelda', 'locale': 'tr-TR', 'quality': 'default', 'identifier': 'a'},
        {'name': 'Cem', 'locale': 'tr-TR', 'quality': 'premium', 'identifier': 'b'},
        {'name': 'Yelda', 'locale': 'tr-TR', 'quality': 'enhanced', 'identifier': 'c'},
      ];
      expect(pickBestVoice(voices, 'tr')!['identifier'], 'b');
    });

    test('başka dildeki kaliteli ses seçilmez', () {
      final voices = [
        {'name': 'Ava', 'locale': 'en-US', 'quality': 'premium'},
        {'name': 'Yelda', 'locale': 'tr-TR', 'quality': 'default'},
      ];
      expect(pickBestVoice(voices, 'tr')!['name'], 'Yelda');
    });

    test('Türkçe ses yoksa ya da liste bozuksa null', () {
      expect(pickBestVoice([], 'tr'), isNull);
      expect(pickBestVoice(['x', {'name': 'Ava'}], 'tr'), isNull);
      expect(
          pickBestVoice([
            {'name': 'Ava', 'locale': 'en-US', 'quality': 'premium'}
          ], 'tr'),
          isNull);
    });

    test('eşitlikte ilk ses; identifier yoksa haritada da yok', () {
      final voices = [
        {'name': 'A', 'locale': 'tr_TR', 'quality': 'enhanced'},
        {'name': 'B', 'locale': 'tr-TR', 'quality': 'enhanced'},
      ];
      final best = pickBestVoice(voices, 'tr')!;
      expect(best['name'], 'A');
      expect(best.containsKey('identifier'), isFalse);
    });
  });

  test('voicesFor yalnızca Türkçe sesleri kaliteyle döndürür', () {
    final voices = [
      {'name': 'Yelda', 'locale': 'tr-TR', 'quality': 'enhanced'},
      {'name': 'Ava', 'locale': 'en-US', 'quality': 'premium'},
      {'name': 'Cem', 'locale': 'tr_TR'},
      'bozuk',
    ];
    final tr = voicesFor(voices, 'tr');
    expect(tr.map((v) => v.name), ['Yelda', 'Cem']);
    expect(tr.first.quality, 'enhanced');
    expect(tr.last.quality, '');
  });

  group('chooseVoice', () {
    final voices = [
      {'name': 'Yelda', 'locale': 'tr-TR', 'quality': 'enhanced', 'identifier': 'yelda'},
      {'name': 'Cem', 'locale': 'tr-TR', 'quality': 'default', 'identifier': 'cem'},
      {'name': 'Ava', 'locale': 'en-US', 'quality': 'premium', 'identifier': 'ava'},
    ];

    test('otomatikte en kaliteli Türkçe ses', () {
      expect(chooseVoice(voices, 'tr', '')!['identifier'], 'yelda');
    });

    test('seçilen ses daha düşük kaliteli olsa da seçilir', () {
      expect(chooseVoice(voices, 'tr', 'cem')!['identifier'], 'cem');
    });

    test('silinmiş ya da başka dildeki ses: otomatiğe düşer', () {
      expect(chooseVoice(voices, 'tr', 'yok')!['identifier'], 'yelda');
      expect(chooseVoice(voices, 'tr', 'ava')!['identifier'], 'yelda');
    });

    test('kimliği olmayan seste ad anahtar olur', () {
      final named = [
        {'name': 'A', 'locale': 'tr-TR', 'quality': 'enhanced'},
        {'name': 'B', 'locale': 'tr-TR'},
      ];
      expect(chooseVoice(named, 'tr', 'B')!['name'], 'B');
      expect(voicesFor(named, 'tr').last.id, 'B');
    });
  });
}
