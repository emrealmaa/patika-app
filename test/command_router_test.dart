import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/command_router.dart';
import 'package:patika_app/commands/intent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommandRouter', () {
    late CommandRouter router;

    setUp(() {
      router = CommandRouter();
    });

    test('SAAT niyeti platform eklentisi olmadan da çalışır (saf Dart)', () async {
      final result = await router.route(
        BleCommand.fromWire('SAAT', null),
      );
      expect(result.success, isTrue);
      expect(result.message, startsWith('Saat '));
    });

    test('BİLİNMİYOR niyeti bilgilendirici bir hata döner', () async {
      final result = await router.route(
        BleCommand.fromWire('BİLİNMİYOR', null),
      );
      expect(result.success, isFalse);
      expect(result.message, 'Bu komutu anlayamadım');
    });

    test('ARA entity olmadan güvenli şekilde başarısız olur', () async {
      final result = await router.route(BleCommand.fromWire('ARA', null));
      expect(result.success, isFalse);
      expect(result.message, 'Kimi arayacağımı anlayamadım');
    });

    // Bu test ortamında flutter_contacts'ın platform kanalı hiç
    // mock'lanmadı, yani ContactResolver.findByName() gerçekten bir
    // MissingPluginException fırlatıyor (widget testlerinin aksine, plain
    // test() FakeAsync kullanmadığı için bu istisna normal şekilde
    // yayılıp yakalanabiliyor). Asıl doğrulanan şey: CommandRouter.route
    // bunu yutup uygulamayı/komut akışını çökertmeden bilgilendirici bir
    // ActionResult.fail döndürüyor - patika Python kod tabanının kendi
    // "asla çökmesin" ilkesiyle aynı ruh (bkz. NOTES.md).
    test(
        'ARA rehber plugin hatası fırlatsa bile route() çökmeden bilgilendirici sonuç döner',
        () async {
      final result = await router.route(
        BleCommand.fromWire('ARA', 'Emre'),
      );
      expect(result.success, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('BİLİNMİYOR: duyulan metin varsa tek cümlede söylenir', () async {
      final result = await router.route(
        BleCommand.fromWire('BİLİNMİYOR', 'uçan halı'),
      );
      expect(result.message, '"uçan halı" komutunu anlayamadım');
    });

    test('Bilinmeyen bir wire değeri BİLİNMİYOR olarak ele alınır', () async {
      final result = await router.route(
        BleCommand.fromWire('YENİ_BİR_NİYET', null),
      );
      expect(result.success, isFalse);
      expect(result.message, 'Bu komutu anlayamadım');
    });

    test('PatikaIntent.fromWireName tüm bilinen niyetleri doğru eşler', () {
      expect(PatikaIntent.fromWireName('ARA'), PatikaIntent.ara);
      expect(PatikaIntent.fromWireName('MESAJ'), PatikaIntent.mesaj);
      expect(PatikaIntent.fromWireName('HAVA'), PatikaIntent.hava);
      expect(PatikaIntent.fromWireName('SAAT'), PatikaIntent.saat);
      expect(PatikaIntent.fromWireName('MÜZİK'), PatikaIntent.muzik);
      expect(PatikaIntent.fromWireName('HABER'), PatikaIntent.haber);
      expect(PatikaIntent.fromWireName('OKU'), PatikaIntent.oku);
      expect(PatikaIntent.fromWireName('GECIS_MODU'), PatikaIntent.gecisModu);
      expect(PatikaIntent.fromWireName('NAVİGASYON'), PatikaIntent.navigasyon);
      expect(PatikaIntent.fromWireName('AYAR'), PatikaIntent.ayar);
      expect(PatikaIntent.fromWireName('BİLİNMİYOR'), PatikaIntent.bilinmiyor);
    });
  });
}
