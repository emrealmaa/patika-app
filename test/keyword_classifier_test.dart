import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';

/// Ağırlıklı anahtar kelime sınıflandırıcısı: gündelik söyleyiş çeşitliliği
/// ve niyetler arası çakışmalar. (cümle, beklenen niyet, beklenen kişi/yer)
void main() {
  void check(List<(String, PatikaIntent, String?)> cases) {
    for (final (text, intent, entity) in cases) {
      final c = classifyVoiceCommand(text);
      expect((c.intent, c.entity), (intent, entity), reason: '"$text"');
    }
  }

  const saat = PatikaIntent.saat;
  const ara = PatikaIntent.ara;
  const mesaj = PatikaIntent.mesaj;
  const hava = PatikaIntent.hava;
  const nav = PatikaIntent.navigasyon;
  const muzik = PatikaIntent.muzik;
  const haber = PatikaIntent.haber;
  const oku = PatikaIntent.oku;
  const gecis = PatikaIntent.gecisModu;
  const yok = PatikaIntent.bilinmiyor;

  group('38 cümlelik hedef tablo (önceki sınıflandırıcı: 19/38)', () {
    test('SAAT', () => check([
          ('saat kaç', saat, null),
          ('saati söyler misin', saat, null),
          ('kaç oldu saat', saat, null),
          ('saat kaçta', saat, null),
          ('şu an saat kaç', saat, null),
        ]));

    test('ARA', () => check([
          ("Ahmet'i ara", ara, 'Ahmet'),
          ("Ahmet'i arar mısın", ara, 'Ahmet'),
          // Kesmesiz ek atılmıyor (karar c) - Faz 3.2 kök bulucuyla çözülecek.
          ('annemi arayabilir misin', ara, 'annemi'),
          ("Ayşe'yi arasana", ara, 'Ayşe'),
          ('Emre ile görüşmek istiyorum', ara, 'Emre'),
        ]));

    test('MESAJ', () => check([
          ("Ayşe'ye mesaj at", mesaj, 'Ayşe'),
          ("Ayşe'ye bir mesaj yazar mısın", mesaj, 'Ayşe'),
          ('annemle mesajlaş', mesaj, 'annem'),
          ("Emre'ye SMS gönder", mesaj, 'Emre'),
        ]));

    test('HAVA', () => check([
          ('hava nasıl', hava, null),
          ('bugün hava nasıl olacak', hava, null),
          ('yağmur yağacak mı', hava, null),
          ('dışarısı soğuk mu', hava, null),
          ('havalar nasıl', hava, null),
        ]));

    test('NAVİGASYON', () => check([
          ('Kadıköy iskelesine götür', nav, 'Kadıköy iskelesi'),
          ('Kadıköy iskelesine nasıl giderim', nav, 'Kadıköy iskelesi'),
          ('eve gitmek istiyorum', nav, 'ev'),
          ('beni hastaneye götürür müsün', nav, 'hastane'),
          ('havaalanına götür', nav, 'havaalanı'),
          ('okula götür', nav, 'okul'),
          ('saat kulesine götür', nav, 'saat kulesi'),
        ]));

    test('MÜZİK / HABER / OKU', () => check([
          ('müzik aç', muzik, null),
          ('bir şarkı çal', muzik, null),
          ('müziği aç', muzik, null),
          ('haberleri oku', haber, null),
          ('bugün neler olmuş', haber, null),
          ('son dakika haberleri', haber, null),
          ('bunu oku', oku, null),
          ('önümde ne yazıyor', oku, null),
          ('yazıyı okur musun', oku, null),
        ]));

    test('niyet olmayanlar', () => check([
          ('arabam nerede', yok, null),
          ('arada bir ara', yok, null),
          ('aralık ayı', yok, null),
        ]));
  });

  group('çakışmalar', () {
    test('benzer kelimeler anahtar kelime sayılmaz', () => check([
          ('araba al', yok, null), // ara != araba
          ('havaalanına götür', nav, 'havaalanı'), // hava != havaalanı
          ('okula götür', nav, 'okul'), // oku != okula
          ('saatçiye uğradım', yok, null), // saat != saatçi
          ('ders çalışıyorum', yok, null), // çal != çalış
        ]));

    test('kişi/yer adayı yoksa eylem niyeti kaybeder', () => check([
          ('haberleri ara', haber, null), // "haberleri" kişi değil
          ('saat kaçta gitmeliyim', saat, null), // gidilecek yer yok
          ('görüşürüz', yok, null), // veda, arama değil
        ]));

    test('yönelme ekli yer navigasyonu öne çıkarır', () => check([
          ('saat kulesine götür', nav, 'saat kulesi'),
          ("Ankara'ya git", nav, 'Ankara'),
        ]));

    test('eşitlikte tablo sırası: kişi gerektiren eylem önde', () => check([
          ('müzik öğretmenimi ara', ara, 'müzik öğretmenimi'),
        ]));

    test('geçiş modu', () => check([
          ('karşıya geçmek istiyorum', gecis, null),
          ('yolu geçmek istiyorum', gecis, null),
        ]));

    test('tek başına zayıf kelime yetmez', () => check([
          ('aç', yok, null),
          ('gönder', yok, null),
          ('soğuk', yok, null),
        ]));
  });
}
