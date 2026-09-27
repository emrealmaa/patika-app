import 'package:flutter/foundation.dart';

import '../ble/ble_command.dart';
import '../settings/settings.dart';
import 'intent.dart';
import 'intent_lexicon.dart';

/// Telefon mikrofonundan gelen serbest metni (örn. "Ahmet'i arar mısın")
/// niyet + entity'ye çeviren, tamamen yerel sınıflandırıcı. Üç katman:
///
/// 1. Kontrol komutları (SOS, DUR, TEKRAR, KOMUTLAR, EĞİTİM) - katı
///    kalıplar, her şeyden önce. Güvenlik: "durum" konuşmayı kesmesin.
/// 2. Ayar komutları (AYAR) - katı kalıplar.
/// 3. Diğer niyetler - AĞIRLIKLI ANAHTAR KELİME puanlaması
///    (tablo: `intent_lexicon.dart`). İnsanlar aynı şeyi çok farklı söyler
///    ("saat kaç", "saati söyler misin", "kaç oldu saat"); sabit kalıplar
///    yerine anahtar kelimelerin geçmesine bakılıyor:
///    - Her niyet, cümledeki anahtar kelimelerinin ağırlığı kadar puan alır
///      (Türkçe ekleri tanır: "saati", "arar mısın", "götürür müsün").
///    - Kişi/yer gerektiren niyet (ARA/MESAJ/NAVİGASYON) gerçek bir aday
///      yoksa 1 puan kaybeder ("haberleri ara" -> HABER); yönelme ekli bir
///      yer 1 puan ekler ("saat kulesine götür" -> NAVİGASYON).
///    - En yüksek puan kazanır; eşitlikte tablo sırası; [minIntentScore]
///      altı BİLİNMİYOR.
///
/// Python intent_classifier.py'den bilinçli farklar: Türkçe'ye uygun küçük
/// harf, entity'nin ORİJİNAL metinden (büyük/küçük harf korunarak)
/// alınması, ARA'da ekin yalnızca kesme işaretinden sonra atılması
/// ("Ali ara" -> "Ali"; "annemi ara" -> "annemi", Faz 3.2 kök bulucuya kadar).
BleCommand classifyVoiceCommand(String text) {
  final original = _normalizeSpacing(text);
  final lowered = _turkishLower(original);
  // Bilinen tek istisna dışında dönüşüm uzunluğu koruyor; korumadıysa
  // indeksler güvenilmez, entity küçük harfli metinden alınır.
  final source = lowered.length == original.length ? original : lowered;

  final control = _controlIntent(lowered, dictation: false);
  if (control != null) return BleCommand.fromWire(control, null);

  for (final (pattern, action) in _settingRules) {
    if (pattern.hasMatch(lowered)) {
      return BleCommand.fromWire('AYAR', action.name);
    }
  }

  if (_lastSentMessage.hasMatch(lowered)) return BleCommand.fromWire('SON_MESAJ', null);

  final alias = _aliasCommand(lowered, source);
  if (alias != null) return BleCommand.fromWire('TAKMA_AD', alias);

  return _classifyByKeywords(lowered, source);
}

// Türkçe harfleri de kapsayan kelime sınırları (Dart'ta \b sadece ASCII).
const _s = r'(?<!\p{L})';
const _e = r'(?!\p{L})';
// Kısa kontrol komutlarının başına/sonuna eklenebilen nezaket sözcükleri.
const _polite = r'(?:lütfen\s+|tamam\s+)?';
const _politeEnd = r'(?:\s+lütfen)?';

/// Evrensel kontrol komutları - her şeyden ÖNCE denetleniyor.
///
/// SOS normalde cümlenin HERHANGİ bir yerinde eşleşiyor: acil durumdaki
/// birinin yanlışlıkla başka bir komuta düşmesi, yardım isteyen birinin
/// (Faz 7'de iptal edilebilir geri sayımlı) SOS'a düşmesinden çok daha kötü.
///
/// DUR/TEKRAR ise yalnızca TÜM cümle o komutsa eşleşiyor: "durum", "Ahmet'e
/// dur de" ya da "tekrar ara" gibi cümleler konuşmayı kesmesin.
///
/// Dikte sırasında (mesaj gövdesi yazdırılırken, [_controlRulesDictation])
/// SOS de aynı "tüm cümle" kuralına tabi: aksi halde "acil durumda beni ara
/// diye yaz" gibi dikte edilen bir mesaj içeriği SOS sanılıp mesaj
/// kaybolurdu. Dikte dışı diyalog cevaplarında (isim, onay) güvenlik-önce
/// davranış aynen kalıyor.
final _controlRuleDefs = [
  ('$_s(?:yardım|imdat)$_e|acil\\s+durum', 'SOS'),
  ('^$_polite(?:dur|durdur|sus|kes|iptal(?:\\s+et)?|vazgeç|yeter)$_politeEnd\$', 'DUR'),
  ('^$_polite(?:tekrar\\s+(?:et|söyle|oku)|tekrarla|bir\\s+daha\\s+söyle|ne\\s+dedin)$_politeEnd\$',
      'TEKRAR'),
  (r'ne\s+yapabilir(?:im|sin)|neler\s+yapabilir(?:im|sin)|komutlar|nasıl\s+kullanılır',
      'KOMUTLAR'),
  (r'eğitim\p{L}*\s+(?:başlat|aç|tekrarla|dinle)', 'EĞİTİM'),
];

final _controlRules =
    _controlRuleDefs.map((r) => (RegExp(r.$1, unicode: true), r.$2)).toList();

final _controlRulesDictation = [
  ('^$_polite(?:yardım|imdat)$_politeEnd\$|^$_polite(?:acil\\s+durum)$_politeEnd\$', 'SOS'),
  ..._controlRuleDefs.skip(1),
].map((r) => (RegExp(r.$1, unicode: true), r.$2)).toList();

/// Telefon ayarları (AYAR niyeti) - entity metinden değil kalıptan geliyor.
/// Diğer kurallardan ÖNCE denetleniyor; hiçbiriyle çakışmıyorlar.
final _settingRules = [
  (r'(?:daha\s+)?hızlı\s+(?:konuş|oku)|konuşmayı\s+hızlandır', SettingAction.speechFaster),
  (r'(?:daha\s+)?yavaş\s+(?:konuş|oku)|konuşmayı\s+yavaşlat', SettingAction.speechSlower),
  (r'(?:daha\s+)?kısa\s+(?:anlat|konuş|söyle)', SettingAction.shorter),
  (r'(?:daha\s+)?(?:uzun|ayrıntılı|detaylı)\s+(?:anlat|konuş|söyle)', SettingAction.longer),
  (r'titreşim\p{L}*\s+kapat', SettingAction.hapticOff),
  (r'titreşim\p{L}*\s+(?:artır|arttır|güçlendir|yükselt)', SettingAction.hapticStronger),
  (r'titreşim\p{L}*\s+(?:azalt|hafiflet|düşür)', SettingAction.hapticWeaker),
].map((r) => (RegExp(r.$1, unicode: true), r.$2)).toList();

// --- Takma ad komutları (katı, puanlamadan önce) -------------------------------

/// "gönderdiğim son mesajı oku", "son gönderdiğim mesaj ne". Gelen
/// mesajları okumak ("mesajlarımı oku") Faz 4b'de ayrı bir niyet.
final _lastSentMessage = RegExp(
    r'gönderdiğim\s+(?:son\s+)?mesaj|son\s+gönder(?:diğim|ilen)\s+mesaj',
    unicode: true);

final _aliasList = RegExp(r'takma\s+ad\p{L}*\s+(?:oku|söyle|listele|neler)|takma\s+adlarım',
    unicode: true);
final _accusativeEnd = RegExp(r'y?[ıiuü]$', unicode: true);

/// "annemi Fatma Yılmaz olarak kaydet" -> "kaydet|annem|Fatma Yılmaz"
/// "Fatma Yılmaz'ı annem olarak kaydet" -> "kaydet|Fatma Yılmaz|annem"
/// "takma adları oku" -> "oku";  "annem takma adını sil" -> "sil|annem"
///
/// Hangi parçanın takma ad, hangisinin rehberdeki kişi olduğuna handler
/// rehbere bakarak karar verir (Türkçe'de iki sıra da doğal). Burada yalnızca
/// belirtme ekli parçadan ikiye bölünüyor (önce kesmeli kelime aranır).
String? _aliasCommand(String lowered, String source) {
  if (_aliasList.hasMatch(lowered)) return 'oku';

  final tokens = [
    for (final m in RegExp(r"[\p{L}\p{N}']+", unicode: true).allMatches(lowered))
      _Token(m.group(0)!, m.start, m.end),
  ];
  String original(int from, int to) =>
      [for (var i = from; i < to; i++) source.substring(tokens[i].start, tokens[i].end)].join(' ');

  // "... takma adını sil"
  final takma = tokens.indexWhere((t) => t.lower == 'takma');
  if (takma > 0 &&
      takma + 2 < tokens.length &&
      tokens[takma + 1].lower.startsWith('ad') &&
      tokens[takma + 2].lower.startsWith('sil')) {
    return 'sil|${original(0, takma)}';
  }

  // "... olarak kaydet"
  final olarak = tokens.indexWhere((t) => t.lower == 'olarak');
  if (olarak < 2 ||
      olarak + 1 >= tokens.length ||
      !tokens[olarak + 1].lower.startsWith('kayde')) {
    return null;
  }
  var split = tokens.indexWhere((t) => t.lower.contains("'"));
  if (split < 0 || split >= olarak - 1) {
    split = tokens.indexWhere((t) => _accusativeEnd.hasMatch(t.lower));
  }
  if (split < 0 || split >= olarak - 1) return 'kaydet||';

  var first = original(0, split + 1);
  final apostrophe = first.lastIndexOf("'");
  first = apostrophe > 0
      ? first.substring(0, apostrophe)
      : first.replaceFirst(_accusativeEnd, '');
  return 'kaydet|$first|${original(split + 1, olarak)}';
}

// --- Anahtar kelime motoru ----------------------------------------------------

/// Yalnızca evrensel kontrol katmanı (SOS, DUR, TEKRAR, KOMUTLAR, EĞİTİM):
/// diyalog cevaplarında "dur"/"tekrar et"/SOS'u yakalamak için - cevap
/// ("Ahmet", "evet") niyet sınıflandırıcısına gitmez. [dictation]: mesaj
/// gövdesi dikte ediliyorsa SOS yalnızca TÜM cümle buysa eşleşir.
PatikaIntent? classifyControl(String text, {bool dictation = false}) {
  final intent = _controlIntent(_turkishLower(_normalizeSpacing(text)), dictation: dictation);
  return intent == null ? null : PatikaIntent.fromWireName(intent);
}

String? _controlIntent(String lowered, {bool dictation = false}) {
  final rules = dictation ? _controlRulesDictation : _controlRules;
  for (final (pattern, intent) in rules) {
    if (pattern.hasMatch(lowered)) return intent;
  }
  return null;
}

class _Token {
  final String lower;
  final int start;
  final int end;
  const _Token(this.lower, this.start, this.end);
}

/// İsim kökünden sonra gelebilecek ekler (çoğul, hal, iyelik, -ki):
/// saat|i, saat|in, haber|leri, önüm|deki, bu|nu, karşı|ya.
/// "havaalanı" ("hava" + "alanı") ya da "saatçi" eşleşmez.
final _nounSuffix = RegExp(
  r"^'?(?:l[ae]r)?"
  r"(?:[ıiuü]|y[ıiuü]|n[ıiuü]|[ae]|y[ae]|n[ae]|[dt][ae]|[dt][ae]n|n?[ıiuü]n|"
  r"s[ıiuü]|s[ıiuü]n[ae]?|[ıiuü]?m|l[ae]|yl[ae])?"
  r"(?:[dt][ae]|[dt][ae]n|k[ıi]|[ıiuü]|[ae]|n[ae]|n)?$",
  unicode: true,
);

/// Fiil kökünden sonra gelebilecek çekimler: ara|r, ara|sana, ara|yabilir,
/// ara|yın, git|mek, gid|erim, götür|ür, oku|yor. "araba", "arada",
/// "aralık", "okula", "çalış" eşleşmez.
final _verbSuffix = RegExp(
  r'^(?:|s[ae]n[ae]|s[ıiuü]n(?:l[ae]r)?|y?[ıiuü]n(?:[ıiuü]z)?|'
  r'(?:y?[ae]|[ıiuü])?r(?:[ıiuü]m|[ıiuü]z|s[ıiuü]n(?:[ıiuü]z)?|l[ae]r)?|'
  r'y?[ae]bil\p{L}*|[ıiuü]?yor\p{L}*|m[ae]k\p{L}*|m[ae]l[ıi]\p{L}*|m[ae]|'
  r'm[ae]y[ae]|y?[ae]c[ae][kğ]\p{L}*|y?[ae]l[ıi]m|y?[ae]y[ıi]m|'
  r'[dt][ıiuü]\p{L}*|m[ıiuü]ş\p{L}*|s[ae]|y?[ae]s[ıi]n|[ıiuü]?ver\p{L}*)$',
  unicode: true,
);

/// Kesmesiz yönelme eki: eve, okula, iskelesine, hastaneye.
final _dativeEnd = RegExp(r'[yn]?[ae]$', unicode: true);
final _apostropheSuffix = RegExp(r"'\p{L}*$", unicode: true);
final _comitativeEnd = RegExp(r'y?l[ae]$', unicode: true);

/// "Birlikte" (-le) anlamı taşıyan fiiller: "annemle mesajlaş", "Emre ile görüş".
const _comitativeVerbs = {'mesajlaş', 'görüş', 'konuş'};

bool _keywordMatches(Keyword k, String token) {
  final suffix = k.kind == KeywordKind.noun ? _nounSuffix : _verbSuffix;
  for (final stem in k.stems) {
    if (token.startsWith(stem) && suffix.hasMatch(token.substring(stem.length))) {
      return true;
    }
  }
  return false;
}

/// [token] bu niyetin bir anahtar kelimesiyse en yüksek ağırlığı, değilse 0.
int _weightIn(IntentEntry entry, String token) {
  var best = 0;
  for (final k in entry.keywords) {
    if (k.weight > best && _keywordMatches(k, token)) best = k.weight;
  }
  return best;
}

class _Score {
  final IntentEntry entry;

  /// Sıralama puanı (kişi/yer cezası ve yönelme bonusu dahil).
  final int score;

  /// Yalnızca anahtar kelime ağırlıkları - eşik buna uygulanır: "Ara" tek
  /// başına (kişi yok, sıralama puanı 1) yine ARA'dır ve diyalog "Kimi
  /// arayayım?" diye sorar. Ceza yalnızca niyetler arası sıralamayı etkiler
  /// ("haberleri ara" -> HABER).
  final int keywordScore;
  final Set<int> keywordTokens;
  final Set<String> matchedStems;
  const _Score(this.entry, this.score, this.keywordScore, this.keywordTokens, this.matchedStems);
}

BleCommand _classifyByKeywords(String lowered, String source) {
  final tokens = [
    for (final m in RegExp(r"[\p{L}\p{N}']+", unicode: true).allMatches(lowered))
      _Token(m.group(0)!, m.start, m.end),
  ];

  final scores = <_Score>[];
  for (final entry in intentLexicon) {
    var score = 0;
    final keywordTokens = <int>{};
    final matchedStems = <String>{};
    for (var i = 0; i < tokens.length; i++) {
      if (keywordExceptions.contains(tokens[i].lower)) continue;
      var best = 0;
      for (final k in entry.keywords) {
        if (k.weight > best && _keywordMatches(k, tokens[i].lower)) {
          best = k.weight;
          matchedStems.add(k.stems.first);
        }
      }
      if (best > 0) {
        score += best;
        keywordTokens.add(i);
      }
    }
    if (score == 0) continue;
    final keywordScore = score;

    if (entry.entity != EntityKind.none) {
      // Katı aday: bu niyetin anahtar kelimesi, dolgu kelimesi ya da BAŞKA
      // bir niyetin güçlü anahtar kelimesi olmayan kelimeler. "haberleri ara"
      // da "haberleri" kişi adayı sayılmaz.
      final strict = [
        for (var i = 0; i < tokens.length; i++)
          if (!keywordTokens.contains(i) &&
              !entityFillers.contains(tokens[i].lower) &&
              !intentLexicon.any((other) =>
                  other != entry && _weightIn(other, tokens[i].lower) >= 2))
            i,
      ];
      if (strict.isEmpty) {
        score -= 1;
      } else if (entry.entity == EntityKind.place &&
          _dativeEnd.hasMatch(tokens[strict.last].lower)) {
        score += 1;
      }
    }
    scores.add(_Score(entry, score, keywordScore, keywordTokens, matchedStems));
  }

  // En yüksek puan; eşitlikte tablo sırası (scores tablo sırasında).
  _Score? winner;
  for (final s in scores) {
    if (winner == null || s.score > winner.score) winner = s;
  }
  if (kDebugMode && scores.isNotEmpty) {
    debugPrint('[Intent] "$lowered" -> '
        '${scores.map((s) => '${s.entry.intent}:${s.score}').join(' ')}');
  }
  if (winner == null || winner.keywordScore < minIntentScore) {
    return BleCommand.fromWire('BİLİNMİYOR', null);
  }

  final entry = winner.entry;
  final entity = entry.entity == EntityKind.none
      ? null
      : _extractEntity(tokens, source, winner);
  return BleCommand.fromWire(entry.intent, entity);
}

/// Kazanan niyetin anahtar kelimeleri ve dolgu kelimeleri dışında kalan
/// kelimeler, ORİJİNAL metinden (büyük/küçük harf korunarak).
String? _extractEntity(List<_Token> tokens, String source, _Score winner) {
  final entry = winner.entry;
  final comitative = entry.comitative &&
      winner.matchedStems.any(_comitativeVerbs.contains);
  final dative = entry.intent == 'MESAJ' || entry.entity == EntityKind.place;

  final parts = <String>[];
  var lastHadApostrophe = false;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (winner.keywordTokens.contains(i) || entityFillers.contains(t.lower)) continue;
    var word = source.substring(t.start, t.end);
    lastHadApostrophe = word.contains("'");
    if (lastHadApostrophe) {
      // Kesmeli ek her zaman atılır: Ahmet'i -> Ahmet, Ayşe'ye -> Ayşe.
      word = word.replaceFirst(_apostropheSuffix, '');
    } else if (comitative && _comitativeEnd.hasMatch(t.lower) && word.length > 4) {
      word = word.replaceFirst(_comitativeEnd, ''); // annemle -> annem
    }
    if (word.isNotEmpty) parts.add(word);
  }
  if (parts.isEmpty) return null;

  // Kesmesiz yönelme eki yalnızca son kelimeden ve MESAJ/yer niyetlerinde:
  // anneme -> annem, iskelesine -> iskelesi. ARA'da kesmesiz ek atılmaz
  // ("Ali ara" -> "Ali").
  if (dative && !lastHadApostrophe) {
    final last = parts.last;
    final stripped = last.replaceFirst(_dativeEnd, '');
    if (stripped != last && stripped.length >= 2) parts[parts.length - 1] = stripped;
  }
  return parts.join(' ');
}

/// Noktalama boşluğa, tipografik kesme işaretleri düz kesmeye çevriliyor.
/// Her ikisi de 1:1 karakter değişimi - uzunluk korunuyor.
String _normalizeSpacing(String text) => text
    .replaceAll(RegExp(r'[’‘`´]'), "'")
    .replaceAll(RegExp(r'[.,!?;:]'), ' ')
    .trim();

/// Türkçe'ye uygun küçük harf: önce İ->i ve I->ı, sonra genel dönüşüm.
String _turkishLower(String text) =>
    text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
