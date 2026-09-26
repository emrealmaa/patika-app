/// Söylenen kişi adından olası KÖK ADAYLARI üretir - tek bir kök tahmin
/// etmek yerine (hangisinin doğru olduğuna rehber karar verir):
///
///   "annemi"    -> annemi, annem, anne
///   "Ali"       -> ali, al            (rehberde "Ali" varsa tam eşleşme kazanır)
///   "Mehmet'in" -> mehmet             (kesme işaretinden sonrası her zaman ek)
///   "anneciğim" -> anneciğim, anne
///
/// Böylece kesme işaretsiz ekler de güvenle atılabiliyor: "Ali" hiçbir zaman
/// "Al"a DÜŞMEZ, çünkü orijinal biçim her zaman aday ve daha yüksek puanlı.
/// Kural tabanlı ve bilinçli olarak basit - Zemberek gibi tam bir morfoloji
/// motoru kişi adları için gereksiz (bkz. docs/architecture.md).
library;

/// Sondan atılabilecek ekler, uzundan kısaya (önce uzun olan denensin:
/// "nin" varken "in" ya da "n" ile yetinilmesin).
const _suffixes = [
  // sevgi eki + iyelik (+ hal)
  'ciğime', 'ciğimi', 'ciğimin', 'çığıma', 'çığımı', 'ciğim', 'cığım', 'çiğim', 'çığım',
  // ayrılma / bulunma
  'dan', 'den', 'tan', 'ten', 'da', 'de', 'ta', 'te',
  // birliktelik
  'yla', 'yle', 'la', 'le',
  // tamlayan
  'nın', 'nin', 'nun', 'nün', 'ın', 'in', 'un', 'ün',
  // belirtme
  'yı', 'yi', 'yu', 'yü', 'ı', 'i', 'u', 'ü',
  // yönelme
  'ya', 'ye', 'na', 'ne', 'a', 'e',
  // 1. tekil iyelik (annem, babam)
  'ım', 'im', 'um', 'üm', 'm',
];

/// Bir kökün en az bu kadar harfi kalmalı ("Al" gibi 2 harfli adlar olası).
const _minRootLength = 2;

/// En fazla bu kadar ek üst üste atılır: anne|m|i -> iki katman.
const _maxDepth = 2;

/// [spoken] içindeki SON kelimeye ekler uygulanır (ekler sona gelir);
/// önceki kelimeler aynen kalır: "Ahmet Yılmaz'ı" -> "ahmet yılmaz".
/// Dönen liste: orijinal biçim önce, sonra atılma derinliğine göre; tekrar
/// yok. Küçük harfe (Türkçe'ye uygun) çevrilmiş olarak döner.
List<String> rootCandidates(String spoken) =>
    [for (final (root, _) in rootCandidatesWithDepth(spoken)) root];

/// [rootCandidates] ile aynı; her adayın kaç katman ek atılarak üretildiği
/// de döner (0: orijinal biçim) - eşleştirici derine inen adaya ceza verir.
List<(String, int)> rootCandidatesWithDepth(String spoken) {
  final words = turkishLower(spoken)
      .replaceAll(RegExp(r'[’‘`´]'), "'")
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];

  final prefix = words.length > 1 ? '${words.sublist(0, words.length - 1).join(' ')} ' : '';
  final last = words.last;

  // Kesme işareti: sonrası kesinlikle ek, tek aday.
  final apostrophe = last.indexOf("'");
  if (apostrophe > 0) return [('$prefix${last.substring(0, apostrophe)}', 0)];

  final result = <String, int>{last: 0};
  var frontier = [last];
  for (var depth = 1; depth <= _maxDepth; depth++) {
    final next = <String>[];
    for (final word in frontier) {
      for (final suffix in _suffixes) {
        if (!word.endsWith(suffix)) continue;
        final root = word.substring(0, word.length - suffix.length);
        if (root.length < _minRootLength || result.containsKey(root)) continue;
        result[root] = depth;
        next.add(root);
      }
    }
    frontier = next;
  }
  return [for (final e in result.entries) ('$prefix${e.key}', e.value)];
}

/// Türkçe'ye uygun küçük harf: önce İ->i ve I->ı, sonra genel dönüşüm.
String turkishLower(String text) =>
    text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
