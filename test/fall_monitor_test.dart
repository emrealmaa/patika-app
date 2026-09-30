import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/handlers/status_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/fall/fall_candidate_source.dart';
import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_monitor.dart';
import 'package:patika_app/fall/fall_shadow_log.dart';
import 'package:patika_app/fall/motion_source.dart';
import 'package:patika_app/fall/synthetic_signals.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/sos/sos_controller.dart';

import 'fakes.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'sos_wiring_test.dart' show ayse, ali;
import 'test_harness.dart';

/// Faz 7c-1: gölge monitörü. EN ÖNEMLİ GRUP "SOS'a bağlantı yok": düşme adayı
/// oluştuğunda SOS'un hiçbir şekilde tetiklenmediği, hem davranışla (gerçek
/// SosController, gerçek uygulama bağlantısı) hem kaynak koduyla kilitli.
void main() {
  group('mod varsayılanı', () {
    test('debug -> gölge, release -> kapalı', () {
      expect(defaultFallMode(isDebug: true), FallMode.shadow);
      expect(defaultFallMode(isDebug: false), FallMode.off);
    });

    test('kullanıcının seçimi derleme türünü ezer', () {
      expect(effectiveFallMode(FallMode.off, isDebug: true), FallMode.off);
      expect(effectiveFallMode(FallMode.shadow, isDebug: false), FallMode.shadow);
      expect(effectiveFallMode(null, isDebug: true), FallMode.shadow);
      expect(effectiveFallMode(null, isDebug: false), FallMode.off);
    });

    test('7c-1\'de yalnızca off ve shadow var: SOS tetikleyen bir mod yok', () {
      expect(FallMode.values, [FallMode.off, FallMode.shadow]);
    });
  });

  group('ayarlar', () {
    test('varsayılan: mod seçilmemiş (null), test ses işareti kapalı', () {
      const s = Settings();
      expect(s.fallMode, isNull);
      expect(s.fallShadowEarcon, isFalse);
    });

    test('kaydedilip okunur; seçilmemiş mod JSON\'a yazılmaz', () {
      expect(const Settings().toJson().containsKey('fallMode'), isFalse);
      final s = const Settings().copyWith(fallMode: FallMode.shadow, fallShadowEarcon: true);
      final back = Settings.fromJson(s.toJson());
      expect(back.fallMode, FallMode.shadow);
      expect(back.fallShadowEarcon, isTrue);
      expect(back, s);
    });

    test('tanınmayan mod değeri "seçilmemiş" sayılır (asla SOS modu değil)', () {
      final back = Settings.fromJson({'fallMode': 'on', 'fallShadowEarcon': 'evet'});
      expect(back.fallMode, isNull);
      expect(back.fallShadowEarcon, isFalse);
    });
  });

  group('FallMonitor', () {
    late SyntheticMotionSource motion;
    late PhoneImuFallCandidateSource source;
    late MemoryFallLogStore store;
    late FallShadowLog log;
    late int earcons;
    late bool earconOn;
    late FallMonitor monitor;

    setUp(() {
      motion = SyntheticMotionSource();
      source = PhoneImuFallCandidateSource(motion);
      store = MemoryFallLogStore();
      log = FallShadowLog(store);
      earcons = 0;
      earconOn = false;
      monitor = FallMonitor(
        source: source,
        log: log,
        earconEnabled: () => earconOn,
        playCandidateEarcon: () => earcons++,
      );
    });

    tearDown(() => monitor.dispose());

    // Gerçek sensör zamanı tek yönde akar: her senaryo öncekinden sonra başlar
    // (geri giden zaman dedektörde yok sayılır).
    var clockMs = 0;
    Future<void> feed(SyntheticScenario scenario) async {
      motion.push(syntheticScenario(scenario, startMs: clockMs));
      clockMs += 100000;
      await pumpEventQueue();
    }

    test('kapalıyken sensör kapalı, hiçbir şey kaydedilmez', () async {
      await monitor.setMode(FallMode.off);
      expect(monitor.running, isFalse);
      expect(motion.hasListener, isFalse);
      expect(log.records, isEmpty);
    });

    test('gölge: sensör açılır; mod kapanınca sensör kapanır', () async {
      await monitor.setMode(FallMode.shadow);
      expect(monitor.running, isTrue);
      expect(motion.hasListener, isTrue);
      await monitor.setMode(FallMode.off);
      expect(monitor.running, isFalse);
      expect(motion.hasListener, isFalse);
    });

    test('gölge: aday kayda girer, kaynak adıyla', () async {
      await monitor.setMode(FallMode.shadow);
      await feed(SyntheticScenario.realisticFall);
      expect(log.records.map((r) => r.outcome), [FallOutcome.candidate]);
      expect(log.records.single.source, 'phone_imu');
    });

    test('darbeye ulaşan elenenler de kayda girer (eşik ayarı için)', () async {
      await monitor.setMode(FallMode.shadow);
      await feed(SyntheticScenario.droppedAndPickedUp);
      await feed(SyntheticScenario.impactNoOrientationChange);
      expect(log.records.map((r) => r.outcome), [FallOutcome.movement, FallOutcome.noOrientationChange]);
    });

    test('darbesiz düşüş kayda girmez, yalnızca sayılır', () async {
      await monitor.setMode(FallMode.shadow);
      await feed(SyntheticScenario.fallNoImpact);
      expect(log.records, isEmpty);
      expect(store.writes, 0);
      expect(monitor.noImpactCount, 1);
    });

    test('yürüme ve sert oturma hiçbir şey üretmez', () async {
      await monitor.setMode(FallMode.shadow);
      await feed(SyntheticScenario.walking);
      await feed(SyntheticScenario.hardSit);
      expect(log.records, isEmpty);
      expect(monitor.noImpactCount, 0);
    });

    test('test ses işareti yalnızca ayar açıkken ve yalnızca adayda çalar', () async {
      await monitor.setMode(FallMode.shadow);
      await feed(SyntheticScenario.realisticFall);
      expect(earcons, 0, reason: 'ayar kapalı (varsayılan)');

      earconOn = true;
      await feed(SyntheticScenario.droppedAndPickedUp);
      expect(earcons, 0, reason: 'aday değil, yalnızca elenen');
      await feed(SyntheticScenario.realisticFall);
      expect(earcons, 1);
    });

    test('mod kapatıldıktan sonra gelen geç sonuç yazılmaz', () async {
      await monitor.setMode(FallMode.shadow);
      await monitor.setMode(FallMode.off);
      motion.push(syntheticScenario(SyntheticScenario.realisticFall));
      await pumpEventQueue();
      expect(log.records, isEmpty);
    });

    test('ivmeölçer yoksa gölge "sensör yok" bildirir, kapatınca temizlenir', () async {
      motion.isAvailable = false;
      await monitor.setMode(FallMode.shadow);
      expect(monitor.running, isFalse);
      expect(monitor.sensorUnavailable, isTrue);
      await monitor.setMode(FallMode.off);
      expect(monitor.sensorUnavailable, isFalse);
    });

    test('hızlı mod değişimi sırayla işlenir, son karar geçerli', () async {
      unawaited(monitor.setMode(FallMode.shadow));
      unawaited(monitor.setMode(FallMode.off));
      await monitor.setMode(FallMode.shadow);
      expect(monitor.running, isTrue);
      unawaited(monitor.setMode(FallMode.off));
      await monitor.setMode(FallMode.off);
      expect(monitor.running, isFalse);
    });
  });

  group('SOS\'a bağlantı yok (EN ÖNEMLİ)', () {
    test('gölge modda düşme adayı oluşunca SosController HİÇ tetiklenmez, hiçbir mesaj/arama gitmez', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(
          direct: actions,
          emergencyContacts: const [ayse, ali], // gönderim mümkün olsun: engel yalnızca tasarım
          initial: const Settings(fallMode: FallMode.shadow),
        );
        async.flushMicrotasks();

        // SosController'a dokunan HER şey durum değişimi yapar: faz, geri sayım,
        // gönderim. Dinleyici hiç çağrılmamalı.
        var sosStatusChanges = 0;
        h.app.sos.status.addListener(() => sosStatusChanges++);

        expect(h.app.fall.running, isTrue, reason: 'sensör gerçekten açık (test anlamlı)');
        h.fallMotion.push(syntheticScenario(SyntheticScenario.realisticFall));
        async.flushMicrotasks();
        // Geri sayım/gönderim süreleri de geçsin: geç tetiklenme de yakalansın.
        for (var i = 0; i < 60; i++) {
          async.elapse(const Duration(seconds: 1));
          h.speakAll(async);
        }

        // Aday gerçekten oluştu ve kayda yazıldı...
        expect(h.app.fallLog.records.map((r) => r.outcome), [FallOutcome.candidate]);
        // ...ama SOS'a hiçbir şey olmadı:
        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.app.sos.busy, isFalse);
        expect(h.app.sos.inCountdown, isFalse);
        expect(h.app.sos.offering112, isFalse);
        expect(h.app.sos.callInProgress, isFalse);
        expect(h.app.sos.history, isEmpty);
        expect(sosStatusChanges, 0);
        expect(actions.sms, isEmpty, reason: 'hiçbir SMS gitmedi');
        expect(actions.calls, isEmpty, reason: 'hiçbir arama yapılmadı');
        expect(h.tts.spoken, isEmpty, reason: 'düşme için hiçbir şey söylenmedi');
        h.dispose();
      });
    });

    test('mod kapalıyken de (kontrol) hiçbir şey olmaz: sensör hiç açılmaz', () {
      fakeAsync((async) {
        final actions = FakeDirectActions();
        final h = Harness(
          direct: actions,
          emergencyContacts: const [ayse],
          initial: const Settings(fallMode: FallMode.off),
        );
        async.flushMicrotasks();
        expect(h.app.fall.running, isFalse);
        expect(h.fallMotion.hasListener, isFalse);
        h.fallMotion.push(syntheticScenario(SyntheticScenario.realisticFall));
        async.flushMicrotasks();
        expect(h.app.fallLog.records, isEmpty);
        expect(h.app.sos.phase, SosPhase.idle);
        expect(actions.sms, isEmpty);
        h.dispose();
      });
    });

    test('kaynak kodu: lib/fall/ SOS\'u hiç içe aktarmaz ya da anmaz', () {
      final files = Directory('lib/fall').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(code.toLowerCase().contains('sos'), isFalse, reason: '${f.path} SOS\'a bağlanmış');
      }
    });

    test('kaynak kodu: SosSource.fall yalnızca lib/sos/ içinde; hiçbir yer onunla tetiklemez', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.startsWith('lib/sos/')) continue;
        final code = entity.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        if (code.contains('SosSource.fall')) offenders.add(path);
      }
      expect(offenders, isEmpty,
          reason: '7c-1\'de düşme SOS tetikleyemez; bağlama 7c-2\'de, bilinçli olarak yapılacak');
    });

    test('AppState, düşme algılamayı trigger ile ilişkilendirmez', () {
      final code = File('lib/app_state.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // Düşme monitörüne SosController ya da trigger verilmiyor.
      final start = code.indexOf('fall = FallMonitor(');
      expect(start, greaterThanOrEqualTo(0));
      final block = code.substring(start, code.indexOf(';', start));
      expect(block.contains('sos'), isFalse);
      expect(block.contains('trigger'), isFalse);
    });
  });

  group('uygulama bağlantısı (ayarlar -> monitör)', () {
    test('ayar değişince sensör açılıp kapanır', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(fallMode: FallMode.off));
        async.flushMicrotasks();
        expect(h.fallMotion.hasListener, isFalse);

        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        expect(h.fallMotion.hasListener, isTrue);

        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.off));
        async.flushMicrotasks();
        expect(h.fallMotion.hasListener, isFalse);
        h.dispose();
      });
    });

    test('seçim yapılmamış ayar testte (debug) gölge olur', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings());
        async.flushMicrotasks();
        expect(kDebugMode, isTrue);
        expect(h.app.fall.mode, FallMode.shadow);
        h.dispose();
      });
    });

    test('başlatma sürerken kapanırsa sensör açık kalmaz', () async {
      final motion = SyntheticMotionSource();
      final m = FallMonitor(
        source: PhoneImuFallCandidateSource(motion),
        log: FallShadowLog(MemoryFallLogStore()),
      );
      final pending = m.setMode(FallMode.shadow); // start() yarıda
      m.dispose();
      await pending;
      await pumpEventQueue();
      expect(motion.hasListener, isFalse);
    });

    test('uygulama kapanınca sensör kapanır', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        expect(h.fallMotion.hasListener, isTrue);
        h.dispose();
        async.flushMicrotasks();
        expect(h.fallMotion.hasListener, isFalse);
      });
    });
  });

  group('durum komutu', () {
    test('mod kapalıyken durum cümlesinde düşme algılama yok', () {
      final text = describeStatus(const StatusSnapshot());
      expect(text.toLowerCase().contains('düşme'), isFalse);
    });

    test('gölgede tek cümle eklenir, en sonda', () {
      final text = describeStatus(const StatusSnapshot(fallMode: FallMode.shadow));
      expect(text.endsWith(Tr.statusFallShadow), isTrue, reason: text);
      expect('düşme'.allMatches(text.toLowerCase()), hasLength(1));
    });

    test('gölgede sensör açılamadıysa bu söylenir (kayıt tutuyor denmez)', () {
      final text = describeStatus(const StatusSnapshot(fallMode: FallMode.shadow, fallSensorUnavailable: true));
      expect(text.endsWith(Tr.statusFallShadowNoSensor), isTrue, reason: text);
      expect(text.contains(Tr.statusFallShadow), isFalse);
    });

    test('kapalıyken sensör bayrağı cümleyi değiştirmez', () {
      expect(describeStatus(const StatusSnapshot(fallSensorUnavailable: true)),
          describeStatus(const StatusSnapshot()));
    });

    test('uygulamada: gerçek mod yansır', () {
      fakeAsync((async) {
        final h = Harness(initial: const Settings(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        h.app.submitVoiceCommand(const BleCommand(intent: PatikaIntent.durum));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.join(' '), contains(Tr.statusFallShadow));
        h.dispose();
      });
    });
  });

  group('metin', () {
    test('strings_tr.dart düşme algılama bölümleri (ana + Test Modu) yasaklı kelime içermez', () {
      final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
      for (final header in ['// --- Düşme algılama (Faz 7c)', '// --- Test Modu: düşme algılama (Faz 7c-1)']) {
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
}
