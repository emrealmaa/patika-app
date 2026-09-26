import '../contacts/contact_matcher.dart';
import '../contacts/turkish_stemmer.dart';

enum YesNo { yes, no, unknown }

enum ReviewAction { send, edit, reread, cancel, unknown }

List<String> _tokens(String text) => turkishLower(text)
    .replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

/// Olumsuz kelimeler ÖNCE denetlenir: "hayır arama" içinde "ara" da geçiyor;
/// kararsız bir cevap asla eylemi başlatmamalı.
const _noWords = {'hayır', 'yok', 'istemiyorum', 'istemem', 'vazgeç', 'vazgeçtim',
    'iptal', 'yanlış', 'olmaz', 'gerek', 'değil', 'hayir'};
const _noPrefixes = ['arama', 'gönderme', 'yapma'];
const _yesWords = {'evet', 'olur', 'tamam', 'doğru', 'peki', 'tabii', 'tabi', 'aynen',
    'onaylıyorum', 'onayla', 'he', 'hı', 'hıhı', 'kesinlikle', 'lütfen'};
const _yesPrefixes = ['ara', 'gönder', 'yolla', 'yap'];

/// "evet", "olur", "tamam ara" -> yes; "hayır", "vazgeç", "arama" -> no.
YesNo parseYesNo(String text) {
  final tokens = _tokens(text);
  if (tokens.isEmpty) return YesNo.unknown;
  if (tokens.any((t) => _noWords.contains(t) || _noPrefixes.any(t.startsWith))) {
    return YesNo.no;
  }
  if (tokens.any((t) => _yesWords.contains(t) || _yesPrefixes.any(t.startsWith))) {
    return YesNo.yes;
  }
  return YesNo.unknown;
}

const _ordinals = {
  'birinci': 0, 'ilk': 0, 'bir': 0, '1': 0, 'birincisi': 0, 'ilki': 0,
  'ikinci': 1, 'iki': 1, '2': 1, 'ikincisi': 1,
  'üçüncü': 2, 'üç': 2, '3': 2, 'üçüncüsü': 2,
};
const _lastWords = {'sonuncu', 'son', 'sonuncusu', 'sondaki'};

/// "ikinci", "sonuncu" ya da ad/soyad ("Kaya", "Ahmet Kaya") -> aday sırası;
/// anlaşılmazsa null. Ad yalnızca SORULAN adaylar içinde aranır.
int? parseChoice(String text, List<ContactEntry> candidates) {
  final tokens = _tokens(text);
  for (final t in tokens) {
    final index = _ordinals[t];
    if (index != null && index < candidates.length) return index;
    if (_lastWords.contains(t)) return candidates.length - 1;
  }
  // Önce cümlenin tamamı ("Ahmet Kaya"), sonra kelime kelime ("Yılmaz
  // olan", "Kaya olanı"): iki adaya da uyan kelime ("Ahmet") belirsiz
  // döner ve atlanır.
  const matcher = ContactMatcher();
  for (final query in [text, ...tokens]) {
    final match = matcher.match(query, candidates);
    if (match is ContactFound) return candidates.indexOf(match.contact);
  }
  return null;
}

/// Mesaj geri okunduktan sonra: "evet" (gönder), "düzelt" (yeniden dikte),
/// "tekrar oku", "hayır" (iptal).
ReviewAction parseReview(String text) {
  final tokens = _tokens(text);
  if (tokens.any((t) => t.startsWith('düzelt') || t.startsWith('değiştir') ||
      t == 'yeniden' || t == 'baştan')) {
    return ReviewAction.edit;
  }
  if (tokens.any((t) => t == 'oku' || t.startsWith('okur') || t.startsWith('okusana')) ||
      (tokens.contains('tekrar') && !tokens.any((t) => t.startsWith('gönder')))) {
    return ReviewAction.reread;
  }
  return switch (parseYesNo(text)) {
    YesNo.yes => ReviewAction.send,
    YesNo.no => ReviewAction.cancel,
    YesNo.unknown => ReviewAction.unknown,
  };
}
