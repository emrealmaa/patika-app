import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';

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

  group('BİLİNMİYOR', () {
    test('anlamsız metin', () => expectCommand('merhaba nasılsın', PatikaIntent.bilinmiyor));
    test('boş metin', () => expectCommand('', PatikaIntent.bilinmiyor));
    test('kelime içindeki "saat" eşleşmez', () =>
        expectCommand('saatçiye uğradım', PatikaIntent.bilinmiyor));
  });
}
