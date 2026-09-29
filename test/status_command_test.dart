import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/battery/phone_battery.dart';
import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/commands/handlers/status_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/voice/voice_controller.dart';

import 'navigation_fixtures.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// Faz 7b-2: "durum" / "pil ne kadar" komutu. Sınıflandırıcı (güvenlik: "acil
/// durum" SOS'ta, "dur" DUR'da kalır), özet cümlesi ve uygulamaya bağlantı.
void main() {
  const listenDelay = Duration(milliseconds: 500);

  group('sınıflandırıcı', () {
    test('durum ve pil sorguları DURUM', () {
      for (final text in [
        'durum',
        'Durum?',
        'durum ne',
        'durumum nasıl',
        'genel durum',
        'durum raporu',
        'lütfen durum',
        'pil',
        'pil ne kadar',
        'pilim ne kadar',
        'pilim ne kadar kaldı',
        'pil kaç',
        'pil durumu',
        'pil seviyesi',
        'şarj ne kadar',
        'şarjım kaç',
        'gözlüğün pili kaç',
        'telefonun şarjı ne kadar kaldı',
        'telefon pili ne kadar',
      ]) {
        final cmd = classifyVoiceCommand(text);
        expect(cmd.intent, PatikaIntent.durum, reason: '"$text"');
        expect(cmd.entity, isNull, reason: '"$text" entity');
      }
    });

    test('güvenlik: "acil durum" SOS, "dur" DUR kalır', () {
      expect(classifyVoiceCommand('acil durum').intent, PatikaIntent.sos);
      expect(classifyVoiceCommand('acil durum var').intent, PatikaIntent.sos);
      expect(classifyVoiceCommand('dur').intent, PatikaIntent.dur);
      expect(classifyVoiceCommand('durdur').intent, PatikaIntent.dur);
      expect(classifyVoiceCommand('durum yardım').intent, PatikaIntent.sos,
          reason: 'SOS cümlenin her yerinde, her şeyden önce');
    });

    test('yalnızca tüm cümle: komşu niyetler bozulmadı', () {
      expect(classifyVoiceCommand('hava durumu').intent, PatikaIntent.hava);
      expect(classifyVoiceCommand('ne kadar kaldı').intent, PatikaIntent.navigasyonKalan);
      expect(classifyVoiceCommand('pil almak için markete götür').intent,
          isNot(PatikaIntent.durum));
      expect(classifyVoiceCommand("Ahmet'e pilim bitiyor diye mesaj gönder").intent,
          PatikaIntent.mesaj);
    });

    test('DURUM kontrol niyeti değil (dikte içinde de hiç eşleşmez)', () {
      expect(PatikaIntent.durum.isControl, isFalse);
      expect(classifyControl('pil', dictation: true), isNull);
      expect(classifyControl('durum', dictation: true), isNull);
      expect(classifyControl('durum'), isNull);
    });

    test('wire adı', () {
      expect(PatikaIntent.fromWireName('DURUM'), PatikaIntent.durum);
      expect(PatikaIntent.fromWireName('durum'), PatikaIntent.durum);
    });
  });

  group('özet cümlesi', () {
    test('her şey bilinirken', () {
      expect(
        describeStatus(const StatusSnapshot(
          glassesConnected: true,
          glassesBattery: 76,
          phoneBattery: 54,
          navigationActive: true,
          navigationRemaining: 'Hedefe 450 metre, yaklaşık 6 dakika kaldı',
        )),
        'Gözlük bağlı, pili yüzde 76. Telefon pili yüzde 54. Navigasyon çalışıyor. '
        'Hedefe 450 metre, yaklaşık 6 dakika kaldı',
      );
    });

    test('bilinmeyen uydurulmaz: gözlük bağlı değil, telefon pili okunamadı', () {
      expect(describeStatus(const StatusSnapshot()),
          'Gözlük bağlı değil. Telefon pili okunamadı. Çalışan bir navigasyon yok');
    });

    test('bağlı ama pil henüz gelmedi', () {
      expect(describeStatus(const StatusSnapshot(glassesConnected: true, phoneBattery: 40)),
          startsWith('Gözlük bağlı, pil bilgisi yok. Telefon pili yüzde 40'));
    });

    test('bağlı değilken eski gözlük pili söylenmez', () {
      expect(describeStatus(const StatusSnapshot(glassesBattery: 50)),
          startsWith('Gözlük bağlı değil.'));
    });

    test('şarjda', () {
      expect(describeStatus(const StatusSnapshot(phoneBattery: 20, phoneCharging: true)),
          contains('Telefon pili yüzde 20, şarj oluyor'));
    });

    test('karşıya geçiş duraklaması', () {
      expect(
          describeStatus(const StatusSnapshot(
              navigationActive: true, navigationPaused: true, navigationRemaining: 'Hedefe 100 metre')),
          endsWith('Navigasyon karşıya geçiş için duraklatıldı'));
    });

    test('SOS sürüyorsa en başta söylenir; geçmiş SOS özeti hiç yok', () {
      expect(describeStatus(const StatusSnapshot(sosPhase: SosPhase.countdown)),
          startsWith('Acil durum geri sayımı sürüyor. '));
      expect(describeStatus(const StatusSnapshot(sosPhase: SosPhase.sending)),
          startsWith('Acil durum mesajı gönderiliyor. '));
      expect(describeStatus(const StatusSnapshot()), isNot(contains('Acil')));
    });

    test('yasaklı kelime yok (bilgi kipi, emir yok)', () {
      final samples = [
        for (final g in [false, true])
          for (final nav in [(false, false), (true, false), (true, true)])
            for (final charging in [false, true])
              describeStatus(StatusSnapshot(
                glassesConnected: g,
                glassesBattery: g ? 15 : null,
                phoneBattery: 5,
                phoneCharging: charging,
                navigationActive: nav.$1,
                navigationPaused: nav.$2,
              )),
        describeStatus(const StatusSnapshot(sosPhase: SosPhase.countdown)),
        describeStatus(const StatusSnapshot(sosPhase: SosPhase.sending)),
      ];
      for (final s in samples) {
        expect(bannedIn(s), isEmpty, reason: '"$s"');
      }
    });

    test('strings_tr.dart "Durum komutu" ve "Pil uyarıları" bölümleri yasaklı kelime içermez', () {
      final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
      for (final header in ['// --- Pil uyarıları (Faz 7b)', '// --- Durum komutu (Faz 7b)']) {
        final start = source.indexOf(header);
        expect(start, greaterThanOrEqualTo(0), reason: '$header bulunamadı');
        final next = source.indexOf('\n  // --- ', start + 10);
        final section = source.substring(start, next == -1 ? source.length : next);
        final code = section.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        final literals =
            RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!).toList();
        expect(literals, isNotEmpty);
        for (final text in literals) {
          expect(bannedIn(text), isEmpty, reason: '"$text"');
        }
      }
    });
  });

  group('uygulamada', () {
    String status(Harness h, FakeAsync async) {
      h.app.submitVoiceCommand(BleCommand.fromWire('DURUM', null));
      async.flushMicrotasks();
      h.speakAll(async);
      return h.tts.spoken.last;
    }

    test('gerçek durumu okur: gözlük bağlı + pil, telefon pili, navigasyon', () {
      fakeAsync((async) {
        final h = Harness();
        h.phoneBattery.reading = const PhoneBatteryReading(54);
        h.app.pollPhoneBattery();
        async.flushMicrotasks();

        h.app.connect('SIM-ESP32-S3-0001');
        async.elapse(const Duration(seconds: 3));
        h.speakAll(async);
        h.app.simulator!.dispatchGlassesMessage(const BatteryMessage(76));
        async.flushMicrotasks();

        h.app.navigation.start(testRoute());
        async.flushMicrotasks();
        h.speakAll(async);

        expect(
          status(h, async),
          'Gözlük bağlı, pili yüzde 76. Telefon pili yüzde 54. Navigasyon çalışıyor. '
          'Hedefe 450 metre, yaklaşık 6 dakika kaldı',
        );
        expect(h.app.log.first.intent, PatikaIntent.durum);
        h.app.disconnect();
        h.dispose();
      });
    });

    test('hiçbir şeyi değiştirmez: navigasyon ve konum sürer', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.navigation.start(testRoute());
        async.flushMicrotasks();
        status(h, async);
        expect(h.app.navigation.active, isTrue);
        expect(h.location.isRunning, isTrue);
        h.dispose();
      });
    });

    test('sesle: "pil ne kadar" özeti okur', () {
      fakeAsync((async) {
        final h = Harness();
        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('pil ne kadar');
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, startsWith('Gözlük bağlı değil. Telefon pili'));
        h.dispose();
      });
    });

    test('dikte sırasında "pil" / "durum" mesaj gövdesidir, komut değil', () {
      fakeAsync((async) {
        final h = Harness();
        void answer(String text) {
          h.speakAll(async);
          async.elapse(listenDelay);
          h.speech.say(text);
          async.flushMicrotasks();
        }

        h.app.voice.startListening(ListenSource.screen);
        async.elapse(listenDelay);
        h.speech.say('mesaj gönder');
        async.flushMicrotasks();
        answer('Ayşe');
        expect(h.tts.spoken.last, Tr.dialogWhatToWrite);

        answer('pil');
        expect(h.app.dialogs.active, isTrue);
        expect(h.tts.spoken.last, "Ayşe Demir'e şu mesaj: pil. Göndereyim mi?");
        expect(h.app.log.where((e) => e.intent == PatikaIntent.durum), isEmpty);
        h.dispose();
      });
    });

    test('komut yardımı durum komutunu anlatır', () {
      expect(Tr.helpShort, contains('durum'));
      expect(Tr.helpDetail, contains('pil ne kadar'));
    });
  });
}
