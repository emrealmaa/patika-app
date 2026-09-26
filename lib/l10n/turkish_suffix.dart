/// Kişi adlarına Türkçe hal eki ekler - diyalog soruları doğal olsun:
/// "Ahmet Kaya'yı arayayım mı?", "Ayşe Demir'e göndereyim mi?".
///
/// Özel ad olduğu için ek kesme işaretiyle ayrılır ve ünsüz yumuşaması
/// yapılmaz. Ünlü uyumu son ünlüye göre; ünlüyle biten adda kaynaştırma
/// "y" eklenir. Alıntı kelimelerdeki istisnalar (saat -> saati) kişi
/// adlarında nadir olduğu için ele alınmıyor.
library;

import '../contacts/turkish_stemmer.dart';

/// Belirtme hali: Ahmet'i, Ayşe'yi, Kaya'yı, Öz'ü, Umut'u.
String accusative(String name) {
  final (vowel, endsWithVowel) = _lastVowel(name);
  final suffix = switch (vowel) {
    'a' || 'ı' => 'ı',
    'e' || 'i' => 'i',
    'o' || 'u' => 'u',
    'ö' || 'ü' => 'ü',
    _ => 'i',
  };
  return "${name.trim()}'${endsWithVowel ? 'y' : ''}$suffix";
}

/// Yönelme hali: Ahmet'e, Ayşe'ye, Kaya'ya, Öz'e, Umut'a.
String dative(String name) {
  final (vowel, endsWithVowel) = _lastVowel(name);
  final suffix = switch (vowel) {
    'a' || 'ı' || 'o' || 'u' => 'a',
    _ => 'e',
  };
  return "${name.trim()}'${endsWithVowel ? 'y' : ''}$suffix";
}

const _vowels = 'aeıioöuü';

/// Son ünlü ve adın ünlüyle bitip bitmediği.
(String?, bool) _lastVowel(String name) {
  final lower = turkishLower(name.trim());
  String? vowel;
  for (var i = lower.length - 1; i >= 0; i--) {
    if (_vowels.contains(lower[i])) {
      vowel = lower[i];
      break;
    }
  }
  final endsWithVowel = lower.isNotEmpty && _vowels.contains(lower[lower.length - 1]);
  return (vowel, endsWithVowel);
}
