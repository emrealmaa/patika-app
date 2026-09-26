/// Sesli komut sınıflandırıcısının anahtar kelime tablosu (VERİ - motor
/// `voice_intent_classifier.dart` içinde). Yeni bir söyleyiş eklemek
/// genelde tek satır: ilgili niyete bir [Keyword] eklemek.
///
/// Türkçe'de "kelime geçiyor mu" yetmez: ekler ve benzer kelimeler çakışır
/// ("ara" / "araba" / "arada", "hava" / "havaalanı", "oku" / "okula"). Bu
/// yüzden her anahtar kelime hangi eklerle eşleşeceğini de tanımlar:
/// - [KeywordKind.noun]: isim ekleri (saat, saati, saatin, haberleri)
/// - [KeywordKind.verb]: fiil çekimleri (ara, arar, arasana, arayabilir,
///   arayın) - "araba", "aralık", "arada" eşleşmez.
library;

enum KeywordKind { noun, verb }

class Keyword {
  /// Kök(ler). Ünsüz yumuşaması varsa ikisi de: ['müzik', 'müziğ'].
  final List<String> stems;
  final KeywordKind kind;

  /// 2: niyeti tek başına belirleyen kelime ("saat", "ara", "mesaj").
  /// 1: tek başına yetmeyen, destekleyici kelime ("çal", "gönder", "soğuk").
  final int weight;

  const Keyword(this.stems, this.kind, this.weight);
}

/// Niyetin kişi/yer gerektirip gerektirmediği - puanlama ve entity
/// çıkarımını etkiler.
enum EntityKind { none, person, place }

class IntentEntry {
  final String intent;
  final EntityKind entity;
  final List<Keyword> keywords;

  /// "-le/-la" (birlikte) eki kişi adından atılır: "annemle mesajlaş",
  /// "Emre ile görüş".
  final bool comitative;

  const IntentEntry(this.intent, this.entity, this.keywords, {this.comitative = false});
}

const _n = KeywordKind.noun;
const _v = KeywordKind.verb;

/// Niyetler - puanlar eşitse bu SIRA önceliği belirler. Kişi/yer gerektiren
/// eylemler önde: onlar ancak gerçek bir kişi/yer adayı varsa tam puan
/// alabiliyor (bkz. motor), yoksa 1 puan kaybediyorlar.
const intentLexicon = [
  IntentEntry('MESAJ', EntityKind.person, [
    Keyword(['mesaj'], _n, 2),
    Keyword(['sms'], _n, 2),
    Keyword(['mesajlaş'], _v, 2),
    Keyword(['ileti'], _n, 1),
    Keyword(['gönder'], _v, 1),
    Keyword(['yolla'], _v, 1),
    Keyword(['yaz'], _v, 1),
    Keyword(['at'], _v, 1),
  ], comitative: true),
  IntentEntry('ARA', EntityKind.person, [
    Keyword(['ara'], _v, 2),
    Keyword(['görüş'], _v, 2),
    Keyword(['konuş'], _v, 1),
  ], comitative: true),
  IntentEntry('NAVİGASYON', EntityKind.place, [
    Keyword(['git', 'gid'], _v, 2),
    Keyword(['götür'], _v, 2),
    Keyword(['yönlendir'], _v, 2),
    Keyword(['tarif'], _n, 1),
    Keyword(['yol'], _n, 1),
  ]),
  IntentEntry('GECIS_MODU', EntityKind.none, [
    Keyword(['karşı'], _n, 1),
    Keyword(['geç'], _v, 1),
    Keyword(['kavşak', 'kavşağ'], _n, 1),
    Keyword(['geçit', 'geçid'], _n, 1),
    Keyword(['yol'], _n, 1),
  ]),
  IntentEntry('HABER', EntityKind.none, [
    Keyword(['haber'], _n, 2),
    Keyword(['gündem'], _n, 2),
    Keyword(['neler'], _n, 1),
    Keyword(['ol'], _v, 1),
  ]),
  IntentEntry('OKU', EntityKind.none, [
    Keyword(['oku'], _v, 2),
    Keyword(['yazı'], _n, 2),
    Keyword(['yaz'], _v, 1),
    Keyword(['önüm'], _n, 1),
    Keyword(['bu'], _n, 1),
    Keyword(['bura'], _n, 1),
    Keyword(['tabela'], _n, 1),
  ]),
  IntentEntry('HAVA', EntityKind.none, [
    Keyword(['hava'], _n, 2),
    Keyword(['yağmur'], _n, 2),
    Keyword(['sıcaklık'], _n, 2),
    Keyword(['şemsiye'], _n, 2),
    Keyword(['yağ'], _v, 1),
    Keyword(['kar'], _n, 1),
    Keyword(['soğuk'], _n, 1),
    Keyword(['sıcak'], _n, 1),
    Keyword(['derece'], _n, 1),
    Keyword(['dışarı'], _n, 1),
  ]),
  IntentEntry('SAAT', EntityKind.none, [
    Keyword(['saat'], _n, 2),
  ]),
  IntentEntry('MÜZİK', EntityKind.none, [
    Keyword(['müzik', 'müziğ'], _n, 2),
    Keyword(['şarkı'], _n, 2),
    Keyword(['çal'], _v, 1),
    Keyword(['aç'], _v, 1),
    Keyword(['dinle'], _v, 1),
  ]),
];

/// Kişi/yer adı olmayan, atılacak kelimeler: soru ekleri, nezaket, zamir,
/// soru kelimeleri, zarflar. Anahtar kelime olmalarını engellemez; yalnızca
/// entity'ye girmezler.
const entityFillers = {
  // soru ekleri
  'mı', 'mi', 'mu', 'mü',
  'mısın', 'misin', 'musun', 'müsün',
  'mısınız', 'misiniz', 'musunuz', 'müsünüz',
  // nezaket, zamir, bağlaç
  'lütfen', 'bana', 'beni', 'benim', 'benimle', 'için', 'bir', 'ile', 've',
  'şimdi', 'hemen', 'acaba', 'artık', 'de', 'da',
  // soru kelimeleri
  'ne', 'nasıl', 'nerede', 'nereye', 'kaç', 'kaçta', 'hangi', 'kim',
  'neden', 'niye', 'zaman',
  // zarflar
  'bugün', 'yarın', 'şu', 'an', 'arada', 'tekrar', 'yine', 'daha', 'sonra',
  // istek fiilleri
  'istiyorum', 'isterim', 'ister', 'lazım', 'gerek',
};

/// Tek başına bir niyet için gereken en düşük puan.
const minIntentScore = 2;
