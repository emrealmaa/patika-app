import '../ble/ble_command.dart';

/// Telefon mikrofonundan gelen serbest metni (örn. "Ahmet'i ara") niyet +
/// entity'ye çeviren basit, tamamen yerel regex sınıflandırıcı - Python
/// tarafındaki intent_classifier.py `siniflandir_regex()`'in küçük Dart
/// karşılığı. Kural sırası ve kalıplar oradakiyle aynı; ilk eşleşen kazanır.
///
/// Python sürümünden bilinçli farklar:
/// - Türkçe'ye uygun küçük harf dönüşümü (Dart'ta "İ".toLowerCase() iki
///   karakterli "i̇" üretir) ve entity'nin ORİJİNAL metinden, büyük/küçük
///   harfi korunarak alınması ("Kadıköy İskelesi" -> "Kadıköy İskelesi").
/// - Kelime sınırı Türkçe harfleri tanıyor ("Ankara'ya git" ARA sayılmıyor).
/// - Ekler sadece kesme işaretinden sonra atılıyor ("Ali ara" -> "Ali",
///   Python'daki gibi "Al" değil). Yönelme halinde (MESAJ/NAVİGASYON)
///   kesmesiz ek de atılıyor ("anneme" -> "annem", "iskelesine" -> "iskelesi").
///
/// Serbest/çeşitli cümle kalıplarını yakalayamaz - eşleşme yoksa BİLİNMİYOR
/// döner ve CommandRouter bunu diğer kaynaklardaki gibi işler.
BleCommand classifyVoiceCommand(String text) {
  final original = _normalizeSpacing(text);
  final lowered = _turkishLower(original);
  // Bilinen tek istisna dışında dönüşüm uzunluğu koruyor; korumadıysa
  // indeksler güvenilmez, entity küçük harfli metinden alınır.
  final source = lowered.length == original.length ? original : lowered;

  for (final rule in _rules) {
    for (final pattern in rule.patterns) {
      final m = pattern.firstMatch(lowered);
      if (m == null) continue;
      final entity = m.groupCount >= 1 ? _entityFrom(m, source) : null;
      return BleCommand.fromWire(rule.intent, entity);
    }
  }
  return BleCommand.fromWire('BİLİNMİYOR', null);
}

class _Rule {
  final String intent;
  final List<RegExp> patterns;

  _Rule(this.intent, List<String> patterns)
      : patterns = patterns.map((p) => RegExp(p, unicode: true)).toList();
}

// Türkçe harfleri de kapsayan kelime sınırları (Dart'ta \b sadece ASCII).
const _s = r'(?<!\p{L})';
const _e = r'(?!\p{L})';
// Kesme işaretli herhangi bir ek ("'i", "'ye") ya da kesmesiz yönelme eki
// ("-e/-a", kaynaştırmalı "-ye/-ya", "-ne/-na").
const _dative = r"(?:'\p{L}+|[yn]?[ae])";

final _rules = [
  _Rule('ARA', [
    "^(.+?)(?:'\\p{L}+)?\\s+ara$_e",
    '${_s}ara\\s+(.+)\$',
  ]),
  _Rule('MESAJ', [
    '^(.+?)$_dative\\s+mesaj\\s*(?:gönder|yaz|at)$_e',
    '${_s}mesaj\\s*(?:gönder|yaz|at)\\s+(.+)\$',
  ]),
  _Rule('HAVA', [r'hava\s*durumu', r'hava\s*nasıl']),
  _Rule('SAAT', [r'saat\s*kaç', '${_s}saat$_e']),
  _Rule('MÜZİK', [
    r'müzik\s*(?:çal|aç)',
    r'şarkı\s*(?:çal|aç)',
    r'(?:bir\s*)?şeyler\s*çal',
  ]),
  _Rule('HABER', ['${_s}haber(?:ler)?(?:i)?$_e', r'ne\s*var\s*ne\s*yok']),
  _Rule('OKU', [
    r'(?:önümdeki|onumdeki|karşımdaki)?\s*yaz[ıi]y[ıi]\s*oku',
    r'yaz[ıi]\s*ne',
    r'bunu\s*oku',
  ]),
  _Rule('GECIS_MODU', [
    r'karşı.{0,20}geç',
    r'yolu\s*geç',
    r'kavşa[ğg]ı?\s*geç',
  ]),
  _Rule('NAVİGASYON', [
    '$_s(?:git|götür|yönlendir|yolu\\s*bul)\\s+(.+)\$',
    '^(.+?)$_dative\\s*(?:git|götür)$_e',
  ]),
];

/// Tüm entity grupları kalıplarda ya eşleşmenin başında ya sonunda duruyor;
/// konumu buradan bulunup orijinal (büyük/küçük harfi korunmuş) metinden
/// kesiliyor - Dart'ın Match'i grup indeksi vermiyor.
String? _entityFrom(RegExpMatch m, String source) {
  final group = m.group(1);
  if (group == null) return null;
  final whole = m.group(0)!;
  final start = whole.startsWith(group)
      ? m.start
      : m.end - group.length;
  final raw = source.substring(start, start + group.length);
  return _cleanEntity(raw);
}

String? _cleanEntity(String raw) {
  var entity = raw.trim();
  // "beni Kadıköy'e götür" -> "Kadıköy"
  entity = entity.replaceFirst(
      RegExp(r'^(?:beni|bana)\s+', caseSensitive: false), '');
  // "ara Ahmet'i" / "mesaj gönder Ayşe'ye" gibi sonda kalan kesmeli ek.
  entity = entity.replaceFirst(RegExp(r"'\p{L}*$", unicode: true), '');
  entity = entity.trim();
  return entity.isEmpty ? null : entity;
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
