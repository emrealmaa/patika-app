import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/guidance_engine.dart';
import 'package:patika_app/navigation/guidance_speech.dart';
import 'package:patika_app/navigation/route.dart';

import 'navigation_fixtures.dart';

/// Navigasyonun dil kuralı: yalnızca bilgi kipi, emir yok.
/// Kaynak: patika/MIMARI.md "Çıktı Dilbilgisi" - yasaklı kelimeler; bunlara
/// navigasyona özgü iki ekleme: karşıya geçiş kararı Kavşak Geçiş
/// Asistanına aittir, bu yüzden "güvenli" ve "açık" (yol açık) de yasak.
///
/// Karşılaştırma Türkçe karakterleri ASCII'ye indirger (MIMARI.md "Türkçe
/// karakter tutarlılığı"): yazım varyantı kuralı delemez. Tam kelime eşleşir:
/// "geçiş" ("gecis") ve "geçtim" ("gectim") yasaklı "geç" ("gec") değildir.
const _banned = {
  'dur', 'durun', 'bekle', 'bekleyin', 'gec', 'gecin', 'gecebilirsin',
  'gecebilirsiniz', 'kay', 'kayin', 'don', 'donun', 'yavasla', 'yavaslayin',
  'hizlan', 'hizlanin', 'tamamla', 'tamamlayin', 'ilerle', 'ilerleyin',
  'dikkat', // "dikkat et" de bu kelimeyle yakalanır
  'guvenli', 'acik',
};

String _ascii(String s) {
  const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'İ': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'Ç': 'c', 'Ğ': 'g', 'Ö': 'o', 'Ş': 's', 'Ü': 'u'};
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch);
  }
  return buffer.toString().toLowerCase();
}

/// Cümledeki yasaklı kelimeler (boşsa temiz).
List<String> bannedIn(String sentence) => _ascii(sentence)
    .split(RegExp(r'[^a-z]+'))
    .where(_banned.contains)
    .toList();

/// strings_tr.dart'taki "Navigasyon (Faz 6)" bölümünün metin değerleri
/// (yorum satırları hariç).
List<String> navigationStringLiterals() {
  final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
  final start = source.indexOf('// --- Navigasyon (Faz 6)');
  expect(start, greaterThanOrEqualTo(0), reason: 'Navigasyon bölümü bulunamadı');
  final next = source.indexOf('\n  // --- ', start + 10);
  final section = source.substring(start, next == -1 ? source.length : next);

  final code = section.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  return RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!).toList();
}

void main() {
  group('yasaklı kelime taraması kendini doğruluyor', () {
    test('büyük/küçük harf ve Türkçe/ASCII yazım fark etmez', () {
      expect(bannedIn('Şimdi sağa dön'), ['don']);
      expect(bannedIn('DÖNÜN'), ['donun']);
      expect(bannedIn('sola DONUN'), ['donun']);
      expect(bannedIn('GEÇİN'), ['gecin']);
    });

    test('yasak: donun/gecin/bekle/dur/dikkat', () {
      expect(bannedIn('sağa dönün'), ['donun']);
      expect(bannedIn('karşıya geçin'), ['gecin']);
      expect(bannedIn('Bekle'), ['bekle']);
      expect(bannedIn('şimdi dur'), ['dur']);
      expect(bannedIn('Dikkat et'), ['dikkat']);
      expect(bannedIn('yol açık'), ['acik']);
      expect(bannedIn('güvenli'), ['guvenli']);
      expect(bannedIn('sagi'), isEmpty);
    });

    test('yakın ama farklı kelimeler serbest: geçiş, geçtim, sapıyor, durak', () {
      expect(bannedIn('karşıya geçiş noktası'), isEmpty);
      expect(bannedIn('"geçtim" deyin'), isEmpty);
      expect(bannedIn('rota sağa sapıyor'), isEmpty);
      expect(bannedIn('otobüs durağı'), isEmpty);
    });
  });

  group('Tr navigasyon bölümü', () {
    test('bölüm bulundu ve metin içeriyor', () {
      expect(navigationStringLiterals().length, greaterThan(20));
    });

    test('hiçbir metinde yasaklı kelime yok', () {
      for (final text in navigationStringLiterals()) {
        expect(bannedIn(text), isEmpty, reason: '"$text" yasaklı kelime içeriyor');
      }
    });
  });

  group('üretilen cümleler', () {
    test('tüm olay türleri x tüm manevralar x sokak adı var/yok', () {
      final events = <GuidanceEvent>[
        for (final m in Maneuver.values)
          for (final street in [null, '', 'Bağdat Caddesi'])
            for (final meters in [0.0, 3.0, 15.0, 47.0, 900.0])
              ManeuverAhead(m, street, meters),
        const CrossingAhead(50),
        const CrossingAhead(12),
        const CrossingPoint(),
        const CrossingResumed(),
        const CrossingTimedOut(),
        for (final v in DirectionVerdict.values) DirectionInfo(v),
        const NearDestination(50),
        const NearDestination(1500),
        const Arrived(),
        const OffRoute(),
        const BackOnRoute(),
        const GpsWeak(),
        const GpsRecovered(),
      ];
      for (final e in events) {
        final text = describeEvent(e);
        expect(text, isNotEmpty);
        expect(bannedIn(text), isEmpty, reason: '"$text" yasaklı kelime içeriyor');
      }
    });

    test('tam bir yürüyüşün tüm konuşması + özet + kalan yol', () {
      final route = testRoute();
      final engine = GuidanceEngine(route); // yön teyidi açık (varsayılan)
      final events = walk(engine, walkPath([(0, 0), (0, 200), (150, 200), (170, 200), (170, 300)]));
      final spoken = <String>[
        describeRouteSummary(route, withDirectionNote: true),
        for (final e in events) describeEvent(e),
        describeRemaining(GuidanceEngine(route)),
      ];
      expect(spoken.length, greaterThan(6));
      expect(events.whereType<DirectionInfo>(), isNotEmpty,
          reason: 'yürüyüş yön cümlesini de kapsamalı');
      for (final text in spoken) {
        expect(bannedIn(text), isEmpty, reason: '"$text" yasaklı kelime içeriyor');
      }
    });

    test('geçiş noktasında navigasyon hiçbir güvenlik/karar bilgisi söylemez', () {
      final engine = GuidanceEngine(testRoute());
      final atCrossing = walk(engine, walkPath([(0, 0), (0, 200), (150, 200)]))
          .whereType<CrossingPoint>()
          .map(describeEvent)
          .single;
      final ascii = _ascii(atCrossing);
      for (final word in ['gec ', 'guvenli', 'acik', 'yesil', 'kirmizi', 'arac']) {
        expect('$ascii ', isNot(contains(word)));
      }
    });
  });
}
