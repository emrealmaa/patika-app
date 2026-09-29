import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/battery/battery_monitor.dart';
import 'package:patika_app/l10n/strings_tr.dart';

/// Faz 7b: pil uyarılarının saf mantığı (eşikler, histerezis, hatırlatma,
/// şarj olayları). Konuşma/titreşim ve "meşgul" kuralı `battery_wiring_test.dart`'ta.
void main() {
  late DateTime clock;
  late BatteryMonitor monitor;

  setUp(() {
    clock = DateTime(2026, 9, 29, 12);
    monitor = BatteryMonitor(now: () => clock);
  });

  BatteryAlert? phone(int percent, {bool charging = false}) =>
      monitor.update(BatterySource.phone, percent, charging: charging);
  BatteryAlert? glasses(int percent) => monitor.update(BatterySource.glasses, percent);

  void expectAlert(BatteryAlert? alert, BatteryAlertKind kind, int percent) {
    expect(alert, isNotNull);
    expect(alert!.kind, kind);
    expect(alert.percent, percent);
  }

  group('eşikler', () {
    test('telefon %30 / %15 / %5, gözlük %20 / %10 / %5', () {
      expect(BatteryThresholds.phone.levels, [30, 15, 5]);
      expect(BatteryThresholds.glasses.levels, [20, 10, 5]);
    });

    test('her eşik aşağı geçilince BİR kez konuşur', () {
      expect(phone(80), isNull);
      expect(phone(31), isNull);
      expectAlert(phone(30), BatteryAlertKind.low, 30);
      expect(phone(29), isNull, reason: 'aynı eşik tekrar konuşmaz');
      expect(phone(16), isNull);
      expectAlert(phone(15), BatteryAlertKind.low, 15);
      expect(phone(14), isNull);
      expectAlert(phone(5), BatteryAlertKind.critical, 5);
      expect(phone(4), isNull);
    });

    test('gözlük kendi eşiklerini kullanır: %30 sessiz, %20 konuşur', () {
      expect(glasses(30), isNull);
      expectAlert(glasses(20), BatteryAlertKind.low, 20);
      expectAlert(glasses(10), BatteryAlertKind.low, 10);
      expectAlert(glasses(5), BatteryAlertKind.critical, 5);
    });

    test('ilk okuma eşiğin altındaysa tek uyarı verir (art arda üç cümle değil)', () {
      expectAlert(phone(12), BatteryAlertKind.low, 12);
      expect(phone(11), isNull);
      expect(phone(12), isNull);
    });

    test('ilk okuma kritikse doğrudan kritik uyarı', () {
      expectAlert(glasses(3), BatteryAlertKind.critical, 3);
    });

    test('bir düşüşte birkaç eşik atlanırsa yalnızca en ağırı söylenir', () {
      expect(phone(40), isNull);
      expectAlert(phone(14), BatteryAlertKind.low, 14);
    });

    test('kaynaklar birbirini etkilemez', () {
      expectAlert(glasses(20), BatteryAlertKind.low, 20);
      expectAlert(phone(20), BatteryAlertKind.low, 20);
    });
  });

  group('histerezis: eşik civarında dalgalanan pil spam yapmaz', () {
    test('%15 civarında inip çıkma tekrar konuşturmaz', () {
      expectAlert(phone(15), BatteryAlertKind.low, 15);
      for (final p in [16, 17, 18, 19, 16, 14, 15, 17, 14]) {
        expect(phone(p), isNull, reason: '%$p');
      }
    });

    test('yeterince yükselip (eşik + 5) tekrar düşünce yeniden uyarır', () {
      expectAlert(phone(15), BatteryAlertKind.low, 15);
      expect(phone(20), isNull, reason: 'geri kurulma sessiz');
      expectAlert(phone(14), BatteryAlertKind.low, 14);
    });

    test('kritik eşikten yükselip yeniden düşünce kritik yine söylenir', () {
      expectAlert(glasses(5), BatteryAlertKind.critical, 5);
      expect(glasses(10), isNull);
      expectAlert(glasses(5), BatteryAlertKind.critical, 5);
    });

    test('tüm eşiklerin üstüne çıkınca baştan başlar', () {
      expectAlert(phone(28), BatteryAlertKind.low, 28);
      expect(phone(40), isNull);
      expectAlert(phone(29), BatteryAlertKind.low, 29);
    });
  });

  group('kritik hatırlatma', () {
    test('kritikte 5 dakikada bir hatırlatır, ondan önce sessiz', () {
      expectAlert(phone(5), BatteryAlertKind.critical, 5);
      clock = clock.add(const Duration(minutes: 4, seconds: 59));
      expect(phone(4), isNull);
      clock = clock.add(const Duration(seconds: 1));
      expectAlert(phone(4), BatteryAlertKind.reminder, 4);
      clock = clock.add(const Duration(minutes: 1));
      expect(phone(4), isNull, reason: 'sayaç hatırlatmada yeniden başlar');
      clock = clock.add(const Duration(minutes: 4));
      expectAlert(phone(3), BatteryAlertKind.reminder, 3);
    });

    test('kritik olmayan eşiklerde hatırlatma yok', () {
      expectAlert(phone(15), BatteryAlertKind.low, 15);
      clock = clock.add(const Duration(hours: 1));
      expect(phone(14), isNull);
    });

    test('şarja takılınca hatırlatma susar', () {
      expectAlert(phone(5), BatteryAlertKind.critical, 5);
      clock = clock.add(const Duration(minutes: 10));
      expect(phone(6, charging: true)?.kind, BatteryAlertKind.chargeStarted);
      clock = clock.add(const Duration(minutes: 10));
      expect(phone(7, charging: true), isNull);
    });
  });

  group('şarj olayları (yalnızca telefon)', () {
    test('takıldı bir kez; şarj sürerken tekrar etmez', () {
      expect(phone(50), isNull);
      expectAlert(phone(50, charging: true), BatteryAlertKind.chargeStarted, 50);
      expect(phone(51, charging: true), isNull);
      expect(phone(52, charging: true), isNull);
    });

    test('doldu bir kez, fişten çekilip yeniden takılana kadar tekrar etmez', () {
      expect(phone(98), isNull);
      expect(phone(98, charging: true)?.kind, BatteryAlertKind.chargeStarted);
      expectAlert(phone(100, charging: true), BatteryAlertKind.chargeFull, 100);
      expect(phone(100, charging: true), isNull);
      expect(phone(99), isNull, reason: 'fişten çekildi');
      expect(phone(99, charging: true)?.kind, BatteryAlertKind.chargeStarted);
    });

    test('uygulama zaten şarjdayken açıldıysa "takıldı" / "doldu" denmez', () {
      expect(phone(60, charging: true), isNull);
      expect(phone(61, charging: true), isNull);
      monitor.reset(BatterySource.phone);
      expect(phone(100, charging: true), isNull);
      expect(phone(100, charging: true), isNull);
    });

    test('şarj olayları düşük pil uyarısından ayırt edilir (bayat kalırsa atılır)', () {
      expect(BatteryAlert(BatterySource.phone, BatteryAlertKind.chargeStarted, 50).isChargeEvent,
          isTrue);
      expect(BatteryAlert(BatterySource.phone, BatteryAlertKind.chargeFull, 100).isChargeEvent,
          isTrue);
      expect(BatteryAlert(BatterySource.phone, BatteryAlertKind.low, 15).isChargeEvent, isFalse);
    });

    test('şarjdayken düşük pil uyarısı yok; fişten çekilince eşikler yeniden geçerli', () {
      expect(phone(50), isNull);
      expect(phone(10, charging: true)?.kind, BatteryAlertKind.chargeStarted);
      expect(phone(11, charging: true), isNull, reason: 'şarjdayken düşük uyarısı yok');
      expectAlert(phone(12), BatteryAlertKind.low, 12);
    });

    test('gözlükte (şarj durumu bilinmiyor) şarj olayı üretilmez', () {
      for (final p in [50, 60, 100, 100]) {
        expect(glasses(p), isNull);
      }
    });
  });

  group('sıfırlama', () {
    test('gözlük bağlantısı kopup yeniden bağlanınca eşikler baştan değerlendirilir', () {
      expectAlert(glasses(20), BatteryAlertKind.low, 20);
      expect(glasses(19), isNull);
      monitor.reset(BatterySource.glasses);
      expectAlert(glasses(19), BatteryAlertKind.low, 19);
    });

    test('bir kaynağı sıfırlamak diğerini etkilemez', () {
      expectAlert(phone(20), BatteryAlertKind.low, 20);
      monitor.reset(BatterySource.glasses);
      expect(phone(19), isNull);
    });
  });

  group('cümleler: bilgi kipi, emir yok', () {
    test('uyarı cümleleri yüzdeyi söyler, kullanıcıya emir vermez', () {
      final texts = [
        Tr.glassesBatteryLow(15),
        Tr.glassesBatteryCritical(5),
        Tr.phoneBatteryLow(30),
        Tr.phoneBatteryCritical(5),
        Tr.phoneChargeStarted,
        Tr.phoneChargeFull,
      ];
      const banned = ['edin', 'dikkat', 'acele', 'hemen', 'güvenli', 'durdur', 'bekle'];
      for (final t in texts) {
        for (final w in banned) {
          expect(t.toLowerCase().contains(w), isFalse, reason: '"$t" içinde "$w"');
        }
      }
      expect(Tr.phoneBatteryLow(15), contains('15'));
      expect(Tr.glassesBatteryCritical(5), contains('5'));
    });
  });
}
