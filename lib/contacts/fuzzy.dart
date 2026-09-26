import 'dart:math';

import 'turkish_stemmer.dart';

/// İsim karşılaştırması için normalleştirme: Türkçe'ye uygun küçük harf,
/// Türkçe karakterler sadeleştirilir (konuşma tanıma "Ayse" yazsa da
/// "Ayşe" bulunsun), noktalama atılır, boşluklar teke indirilir.
String normalizeName(String name) {
  const fold = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  final lower = turkishLower(name);
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(fold[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Jaro-Winkler benzerliği (0..1). Kısa isimlerde iyi çalışır ve baştaki
/// ortak harflere ağırlık verir: "mehmet"/"mehmed" yüksek, "mehmet"/"ahmet"
/// düşük.
double jaroWinkler(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;

  final window = max(0, max(a.length, b.length) ~/ 2 - 1);
  final aMatched = List<bool>.filled(a.length, false);
  final bMatched = List<bool>.filled(b.length, false);

  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final from = max(0, i - window);
    final to = min(b.length - 1, i + window);
    for (var j = from; j <= to; j++) {
      if (bMatched[j] || a[i] != b[j]) continue;
      aMatched[i] = bMatched[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;

  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!aMatched[i]) continue;
    while (!bMatched[k]) {
      k++;
    }
    if (a[i] != b[k]) transpositions++;
    k++;
  }

  final m = matches.toDouble();
  final jaro = (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;

  var prefix = 0;
  while (prefix < min(4, min(a.length, b.length)) && a[prefix] == b[prefix]) {
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}
