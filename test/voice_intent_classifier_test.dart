import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/settings/settings.dart';

void main() {
  void expectCommand(String text, PatikaIntent intent, [String? entity]) {
    final cmd = classifyVoiceCommand(text);
    expect(cmd.intent, intent, reason: '"$text" niyeti');
    expect(cmd.entity, entity, reason: '"$text" entity');
  }

  group('ARA', () {
    test('kesmeli ek atılır', () => expectCommand("Ahmet'i ara", PatikaIntent.ara, 'Ahmet'));
    test('kesmesiz isim kesilmez', () => expectCommand('Ali ara', PatikaIntent.ara, 'Ali'));
    test('tipografik kesme ve nokta', () => expectCommand('Ayşe’yi ara.', PatikaIntent.ara, 'Ayşe'));
    test('fiil başta', () => expectCommand('ara Emre', PatikaIntent.ara, 'Emre'));
    test('büyük İ doğru işlenir', () => expectCommand("İsmail'i ARA", PatikaIntent.ara, 'İsmail'));
  });

  group('MESAJ', () {
    test('kesmeli yönelme', () => expectCommand("Ayşe'ye mesaj gönder", PatikaIntent.mesaj, 'Ayşe'));
    test('kesmesiz yönelme', () => expectCommand('anneme mesaj at', PatikaIntent.mesaj, 'annem'));
    test('fiil başta', () => expectCommand("mesaj yaz Emre'ye", PatikaIntent.mesaj, 'Emre'));
  });

  group('NAVİGASYON', () {
    test('kaynaştırmalı yönelme, harf korunur', () => expectCommand(
        'Kadıköy İskelesine götür', PatikaIntent.navigasyon, 'Kadıköy İskelesi'));
    test('"beni" atılır', () => expectCommand('beni eve götür', PatikaIntent.navigasyon, 'ev'));
    test("Ankara'ya git ARA sayılmaz", () =>
        expectCommand("Ankara'ya git", PatikaIntent.navigasyon, 'Ankara'));
    test('fiil başta', () => expectCommand('yönlendir Taksim meydanı', PatikaIntent.navigasyon, 'Taksim meydanı'));
  });

  group('entity gerektirmeyen niyetler', () {
    test('SAAT', () => expectCommand('Saat kaç?', PatikaIntent.saat));
    test('HAVA', () => expectCommand('hava durumu nasıl', PatikaIntent.hava));
    test('MÜZİK', () => expectCommand('müzik çal', PatikaIntent.muzik));
    test('HABER', () => expectCommand('haberleri oku', PatikaIntent.haber));
    test('OKU', () => expectCommand('önümdeki yazıyı oku', PatikaIntent.oku));
    test('GECIS_MODU', () => expectCommand('karşıya geçmek istiyorum', PatikaIntent.gecisModu));
  });

  group('AYAR', () {
    void expectSetting(String text, SettingAction action) =>
        expectCommand(text, PatikaIntent.ayar, action.name);

    test('daha hızlı konuş', () => expectSetting('Daha hızlı konuş', SettingAction.speechFaster));
    test('yavaş konuş', () => expectSetting('biraz yavaş konuş lütfen', SettingAction.speechSlower));
    test('kısa anlat', () => expectSetting('daha kısa anlat', SettingAction.shorter));
    test('ayrıntılı anlat', () => expectSetting('ayrıntılı anlat', SettingAction.longer));
    test('titreşimi artır', () => expectSetting('titreşimi artır', SettingAction.hapticStronger));
    test('titreşimi azalt', () => expectSetting('Titreşimi azalt', SettingAction.hapticWeaker));
    test('titreşimi kapat', () => expectSetting('titreşimi kapat', SettingAction.hapticOff));
    test('diğer niyetleri bozmaz', () => expectCommand("Ahmet'i ara", PatikaIntent.ara, 'Ahmet'));
  });

  group('evrensel komutlar', () {
    test('dur ve eşanlamlıları', () {
      for (final t in ['dur', 'Dur.', 'sus', 'iptal', 'iptal et', 'vazgeç', 'yeter',
          'lütfen dur', 'tamam dur', 'durdur']) {
        expectCommand(t, PatikaIntent.dur);
      }
    });
    test('"durum" ve içinde "dur" geçen cümleler DUR değil', () {
      expect(classifyVoiceCommand('durum').intent, isNot(PatikaIntent.dur));
      expect(classifyVoiceCommand("Ahmet'i ara dur").intent, isNot(PatikaIntent.dur));
      expect(classifyVoiceCommand('mesajı iptal etme').intent, isNot(PatikaIntent.dur));
    });
    test('tekrar et', () {
      for (final t in ['tekrar et', 'tekrarla', 'tekrar söyle', 'bir daha söyle',
          'ne dedin', 'lütfen tekrar et']) {
        expectCommand(t, PatikaIntent.tekrar);
      }
    });
    test('"tekrar ara" TEKRAR değil', () {
      expect(classifyVoiceCommand("Ahmet'i tekrar ara").intent, isNot(PatikaIntent.tekrar));
    });
    test('komut listesi', () {
      expectCommand('ne yapabilirim', PatikaIntent.komutlar);
      expectCommand('neler yapabilirsin', PatikaIntent.komutlar);
      expectCommand('komutları söyle', PatikaIntent.komutlar);
    });
    test('eğitim', () {
      expectCommand('eğitimi başlat', PatikaIntent.egitim);
      expectCommand('eğitimi tekrarla', PatikaIntent.egitim);
    });
    test('SOS her şeyden önce ve cümlenin her yerinde', () {
      expectCommand('yardım', PatikaIntent.sos);
      expectCommand('İmdat!', PatikaIntent.sos);
      expectCommand('acil durum', PatikaIntent.sos);
      expectCommand("yardım edin Ahmet'i ara", PatikaIntent.sos);
    });
    test('"yardımcı" ya da "yardımseverlik" SOS değil', () {
      expect(classifyVoiceCommand('yardımcı ol').intent, isNot(PatikaIntent.sos));
    });
    test('kontrol niyetleri teyitsiz uygulanır', () {
      for (final i in [PatikaIntent.dur, PatikaIntent.tekrar, PatikaIntent.komutlar,
          PatikaIntent.egitim, PatikaIntent.sos]) {
        expect(i.isControl, isTrue, reason: '$i');
      }
      expect(PatikaIntent.ara.isControl, isFalse);
    });
  });

  group('BİLİNMİYOR', () {
    test('anlamsız metin', () => expectCommand('merhaba nasılsın', PatikaIntent.bilinmiyor));
    test('boş metin', () => expectCommand('', PatikaIntent.bilinmiyor));
    test('kelime içindeki "saat" eşleşmez', () =>
        expectCommand('saatçiye uğradım', PatikaIntent.bilinmiyor));
  });
}
