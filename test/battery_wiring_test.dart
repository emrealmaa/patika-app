import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/battery/battery_monitor.dart';
import 'package:patika_app/battery/phone_battery.dart';
import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/sos_controller.dart';

import 'fakes.dart';
import 'navigation_fixtures.dart';
import 'test_harness.dart';

const ayse = EmergencyContact('Ayşe Demir', '0555 000 00 03');
const ali = EmergencyContact('Ali Kaya', '0555 000 00 02');

/// Faz 7b-1: pil uyarılarının uygulamaya bağlanması. Eşik/histerezis mantığının
/// kendisi `battery_monitor_test.dart`'ta. Bu dosyanın kilitlediği kurallar:
/// - pil YALNIZCA uyarır, SOS'u ve navigasyonu asla durdurmaz;
/// - SOS / SOS'un araması / gelen arama / karşıya geçiş sırasında pil uyarısı
///   konuşmaz, ertelenir ve sonra SOS duyurusundan AYRI, sıralı bir duyuru olur;
/// - şarj olayları en düşük öncelikte: kritik bir duyurunun önüne geçmez.
void main() {
  const lowPhone = 'Telefon pili yüzde 14';
  const sosSent = 'Acil durum mesajı 2 kişiye gönderildi';

  Harness direct({FakeDirectActions? actions, BatteryMonitor? monitor}) => Harness(
        direct: actions ?? FakeDirectActions(),
        emergencyContacts: const [ayse, ali],
        batteryMonitor: monitor,
      );

  /// Saniye saniye ilerler; her saniye bekleyen konuşmaları bitirir.
  void advance(Harness h, FakeAsync async, int seconds) {
    for (var i = 0; i < seconds; i++) {
      async.elapse(const Duration(seconds: 1));
      h.speakAll(async);
    }
  }

  /// Telefon pilini [percent] yapıp bir yoklama yapar, konuşmaları akıtır.
  void poll(Harness h, FakeAsync async, int? percent, {bool charging = false}) {
    h.phoneBattery.reading = percent == null ? null : PhoneBatteryReading(percent, charging: charging);
    h.app.pollPhoneBattery();
    async.flushMicrotasks();
    h.speakAll(async);
  }

  int batteryHaptics(Harness h) =>
      h.haptics.played.where((e) => e.$1 == HapticPatternId.batteryLow).length;

  void longPress(Harness h, FakeAsync async) {
    h.app.simulator!.injectButton(GlassesButton.longPress);
    async.flushMicrotasks();
  }

  group('uyarılar', () {
    test('telefon %14: konuşur ve titreşir; eşik tekrar söylenmez', () {
      fakeAsync((async) {
        final h = Harness();
        poll(h, async, 80);
        expect(h.tts.spoken, isEmpty);

        poll(h, async, 14);
        expect(h.tts.spoken, [lowPhone]);
        expect(batteryHaptics(h), 1);

        poll(h, async, 13);
        poll(h, async, 14);
        expect(h.tts.spoken, [lowPhone], reason: 'aynı eşik tekrar konuşmaz');
        h.dispose();
      });
    });

    test('gözlük pili %9 gelince gözlük cümlesiyle konuşur', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.simulator!.dispatchGlassesMessage(const BatteryMessage(9));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken, ['Gözlük pili yüzde 9']);
        expect(h.app.glassesBattery, 9);
        h.dispose();
      });
    });

    test('kritik %5: konuşur; 5 dakika sonra hatırlatma YALNIZCA titreşimdir (ses yok)', () {
      fakeAsync((async) {
        var clock = DateTime(2026, 9, 29, 12);
        final h = direct(monitor: BatteryMonitor(now: () => clock));
        poll(h, async, 5);
        expect(h.tts.spoken, ['Telefon pili çok düşük, yüzde 5']);
        final haptics = batteryHaptics(h);

        clock = clock.add(const Duration(minutes: 5));
        poll(h, async, 5);
        expect(batteryHaptics(h), haptics + 1);
        expect(h.tts.spoken, hasLength(1), reason: 'hatırlatma sessiz');
        h.dispose();
      });
    });

    test('pil okunamazsa sessiz kalır; değer uydurmaz', () {
      fakeAsync((async) {
        final h = Harness();
        poll(h, async, 14);
        poll(h, async, null);
        expect(h.app.phoneBatteryPercent, isNull);
        expect(h.tts.spoken, [lowPhone]);
        h.dispose();
      });
    });

    test('Test Modu taklidi gerçek okumanın yerine geçer, temizlenince gerçeğe döner', () {
      fakeAsync((async) {
        final h = Harness();
        h.phoneBattery.reading = const PhoneBatteryReading(80);
        h.app.phoneBatteryTest.force(const PhoneBatteryReading(14));
        h.app.pollPhoneBattery();
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken, [lowPhone]);

        h.app.phoneBatteryTest.clear();
        h.app.pollPhoneBattery();
        async.flushMicrotasks();
        expect(h.app.phoneBatteryPercent, 80);
        h.dispose();
      });
    });
  });

  group('şarj olayları: en düşük öncelik', () {
    test('takıldı bilgisi titreşimsiz söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        poll(h, async, 80);
        final before = h.haptics.played.length;
        poll(h, async, 80, charging: true);
        expect(h.tts.spoken, ['Telefon şarja takıldı']);
        expect(h.haptics.played.length, before, reason: 'şarj olayı titreşim çalmaz');
        h.dispose();
      });
    });

    test('kritik bir duyuru konuşulurken şarj olayı onu KESMEZ, sonra gelir', () {
      fakeAsync((async) {
        final h = Harness();
        poll(h, async, 80);
        h.app.feedback.say(sosSent, priority: AnnouncementPriority.critical);
        async.flushMicrotasks();
        expect(h.tts.spoken, [sosSent]);

        h.phoneBattery.reading = const PhoneBatteryReading(80, charging: true);
        h.app.pollPhoneBattery();
        async.flushMicrotasks();
        expect(h.tts.stops, 0, reason: 'kritik duyuru kesilmedi');
        expect(h.tts.spoken, [sosSent]);

        h.speakAll(async);
        expect(h.tts.spoken, [sosSent, 'Telefon şarja takıldı']);
        h.dispose();
      });
    });

    test('sıradaki normal bir duyurunun da arkasında kalır (en düşük öncelik)', () {
      fakeAsync((async) {
        final h = Harness();
        poll(h, async, 80);
        h.app.feedback.say(sosSent, priority: AnnouncementPriority.critical);
        async.flushMicrotasks();

        // Şarj bilgisi ÖNCE gelir, normal duyuru sonra: yine de normal önce okunur.
        h.phoneBattery.reading = const PhoneBatteryReading(80, charging: true);
        h.app.pollPhoneBattery();
        async.flushMicrotasks();
        h.app.feedback.say('Komut sonucu', priority: AnnouncementPriority.normal);
        async.flushMicrotasks();

        h.speakAll(async);
        expect(h.tts.spoken, [sosSent, 'Komut sonucu', 'Telefon şarja takıldı']);
        expect(h.tts.stops, 0);
        h.dispose();
      });
    });
    // Bayat kalan `low` duyurunun atılması (10 sn) kuyruğun kendi davranışıdır:
    // `announcement_queue_test.dart`'ta kilitli.
  });

  group('SOS sırasında: uyarı ertelenir, SOS\'tan sonra AYRI duyuru olarak gelir', () {
    test('SOS bitince pil uyarısı SOS duyurusundan SONRA, ayrı bir duyuru olarak gelir', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        poll(h, async, 80);
        longPress(h, async);
        advance(h, async, 2);
        expect(h.app.sos.phase, SosPhase.countdown);

        poll(h, async, 14);
        expect(h.tts.spoken.contains(lowPhone), isFalse, reason: 'geri sayımda konuşmaz');

        advance(h, async, 15); // geri sayım biter, SMS + arama
        expect(actions.calls, [ayse.number]);
        expect(h.app.sos.callInProgress, isTrue);
        poll(h, async, 14);
        expect(h.tts.spoken.contains(lowPhone), isFalse, reason: 'SOS araması sürerken konuşmaz');

        advance(h, async, 45); // arama biter (sahte izleyici: 40 sn)
        expect(h.app.sos.callInProgress, isFalse);
        poll(h, async, 14);

        final sosAt = h.tts.spoken.indexWhere((s) => s.contains(sosSent));
        final batteryAt = h.tts.spoken.indexOf(lowPhone);
        expect(sosAt, isNonNegative);
        expect(batteryAt, greaterThan(sosAt), reason: 'pil uyarısı SOS duyurusundan sonra');
        expect(h.tts.spoken.where((s) => s.contains('Telefon pili')), [lowPhone],
            reason: 'ayrı ve tek bir duyuru');
        expect(h.tts.spoken.where((s) => s.contains(sosSent) && s.contains('Telefon pili')),
            isEmpty,
            reason: 'iki cümle tek cümlede karışmaz');
        h.dispose();
      });
    });

    test('kritik pil SOS\'u DURDURMAZ: geri sayım sürer, mesaj yine gider', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = direct(actions: actions);
        poll(h, async, 3);
        expect(h.tts.spoken, ['Telefon pili çok düşük, yüzde 3']);

        longPress(h, async);
        advance(h, async, 2);
        poll(h, async, 2);
        expect(h.app.sos.phase, SosPhase.countdown, reason: 'pil geri sayımı iptal etmez');

        advance(h, async, 15);
        expect(actions.sms.map((s) => s.$1), [ayse.number, ali.number]);
        expect(actions.calls, [ayse.number]);
        h.dispose();
      });
    });
  });

  group('navigasyon', () {
    void startNav(Harness h, FakeAsync async) {
      h.app.navigation.start(testRoute());
      async.flushMicrotasks();
    }

    void walkToCrossing(Harness h, FakeAsync async) {
      for (final (x, y) in walkPath([(0, 0), (0, 200), (140, 200)])) {
        h.location.emit(enu(x, y));
        async.elapse(const Duration(seconds: 1));
        h.speakAll(async);
      }
    }

    test('kritik pil navigasyonu DURDURMAZ; yalnızca uyarır', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        poll(h, async, 3);
        expect(h.tts.spoken.last, 'Telefon pili çok düşük, yüzde 3');
        expect(h.app.navigation.active, isTrue);
        expect(h.location.isRunning, isTrue);
        h.dispose();
      });
    });

    test('karşıya geçiş duraklamasında uyarı ertelenir; "geçtim" sonrası söylenir', () {
      fakeAsync((async) {
        final h = Harness();
        startNav(h, async);
        walkToCrossing(h, async);
        expect(h.app.navigation.isPausedForCrossing, isTrue);

        poll(h, async, 14);
        expect(h.tts.spoken.contains(lowPhone), isFalse, reason: 'kavşakta konuşmaz');
        expect(h.app.navigation.isPausedForCrossing, isTrue, reason: 'pil duraklamayı bozmaz');

        h.app.submitVoiceCommand(BleCommand.fromWire('GECTIM', null));
        async.flushMicrotasks();
        h.speakAll(async);
        poll(h, async, 14);
        expect(h.tts.spoken.where((s) => s == lowPhone), hasLength(1));
        expect(h.app.navigation.active, isTrue);
        h.dispose();
      });
    });
  });

  group('gelen arama', () {
    test('telefon çalarken pil uyarısı ertelenir', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.callSimulator!.startCall('Ahmet Yılmaz');
        async.flushMicrotasks();
        h.speakAll(async);
        final spokenBefore = h.tts.spoken.length;

        poll(h, async, 14);
        expect(h.tts.spoken.length, spokenBefore);
        expect(h.tts.spoken.contains(lowPhone), isFalse);
        h.dispose();
      });
    });
  });
}
