import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_act.dart';
import 'package:patika_app/fall/fall_candidate_source.dart';
import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_monitor.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/sos/fall_sos_bridge.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';

import 'sos_test.dart' show Rig, ayse, ali;

/// Faz 7c-2, adım 5: düşme adayı -> SOS köprüsü. Gerçek `SosController`
/// (sahte gönderim ve announcer ile). EN ÖNEMLİ: yalnızca `on` + silahlı +
/// gerçek kaynakta tetikler; bastırma iptal anından 2 dk; süren SOS'u kesmez.
void main() {
  FallCandidate candidate({String source = 'phone_imu'}) => FallCandidate(
        source: source,
        evaluation: const FallEvaluation(
          outcome: FallOutcome.candidate,
          startMs: 0,
          freeFallMs: 400,
          peakG: 3.2,
          orientationDegrees: 70,
          stillnessStdG: 0.02,
        ),
      );

  late StreamController<FallCandidate> stream;
  late Rig rig;
  late FallMode mode;
  late bool armed;
  late int interrupts;
  late DateTime now;
  late List<(FallCandidate, FallAct)> acts;
  late FallSosBridge bridge;

  void build() {
    stream = StreamController<FallCandidate>.broadcast(sync: true);
    rig = Rig();
    mode = FallMode.on;
    armed = true;
    interrupts = 0;
    now = DateTime(2026, 10, 10, 12);
    acts = [];
    bridge = FallSosBridge(
      candidates: stream.stream,
      sos: rig.controller,
      mode: () => mode,
      armed: () => armed,
      interruptOrdinary: () async => interrupts++,
      onAct: (c, a) => acts.add((c, a)),
      now: () => now,
    );
    rig.outcomeSink = bridge.onSosOutcome;
  }

  void emit(FakeAsync async, [FallCandidate? c]) {
    stream.add(c ?? candidate());
    async.flushMicrotasks();
  }

  void run(FakeAsync async, Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  void dispose() {
    bridge.dispose();
    rig.dispose();
    stream.close();
  }

  List<FallAct> actNames() => [for (final (_, a) in acts) a];

  group('tetikleme koşulları', () {
    test('açık + silahlı + gerçek kaynak: düşme kaynaklı 25 sn geri sayım başlar, `started`', () {
      fakeAsync((async) {
        build();
        emit(async);
        expect(rig.controller.phase, SosPhase.countdown);
        expect(rig.controller.status.value.source, SosSource.fall);
        expect(rig.log, contains('countdown(fall,25)'));
        expect(actNames(), [FallAct.started]);
        expect(rig.direct.sms, isEmpty, reason: 'geri sayım bitmeden gitmez');
        dispose();
      });
    });

    test('iptal edilmezse 25 sn sonra SMS + ilk kişi aranır; 112 kendiliğinden ARANMAZ; `sent`', () {
      fakeAsync((async) {
        build();
        rig.call112 = true; // 112 ayarı açık olsa bile düşmede kendiliğinden aranmaz
        emit(async);
        run(async, const Duration(seconds: 24));
        expect(rig.direct.sms, isEmpty);
        run(async, const Duration(seconds: 30));
        expect(rig.direct.sms, isNotEmpty);
        expect(rig.direct.calls, isNot(contains('112')));
        expect(actNames(), [FallAct.started, FallAct.sent]);
        dispose();
      });
    });

    test('GÖLGE modunda hiçbir şey olmaz', () {
      fakeAsync((async) {
        build();
        mode = FallMode.shadow;
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        expect(acts, isEmpty);
        expect(rig.log, isEmpty);
        dispose();
      });
    });

    test('KAPALI modda hiçbir şey olmaz', () {
      fakeAsync((async) {
        build();
        mode = FallMode.off;
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        expect(acts, isEmpty);
        dispose();
      });
    });

    test('SİLAHLI değilse (ayar dosyasındaki "on" kapı doğrulanmadan) hiçbir şey olmaz', () {
      fakeAsync((async) {
        build();
        armed = false;
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        expect(acts, isEmpty);
        expect(rig.log, isEmpty);
        dispose();
      });
    });

    test('SENTETİK kaynak asla eyleme dönmez (açık + silahlı olsa bile)', () {
      fakeAsync((async) {
        build();
        emit(async, candidate(source: fallSyntheticSourceId));
        run(async, const Duration(minutes: 2));
        expect(rig.controller.phase, SosPhase.idle);
        expect(acts, isEmpty);
        expect(rig.direct.sms, isEmpty);
        expect(rig.direct.calls, isEmpty);
        dispose();
      });
    });

    test('mod geri sayımdan önce değişirse sonraki aday tetiklemez', () {
      fakeAsync((async) {
        build();
        emit(async);
        rig.controller.cancel(SosCancelSource.voice);
        now = now.add(const Duration(minutes: 3));
        mode = FallMode.shadow;
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        dispose();
      });
    });
  });

  group('bastırma (karar 7)', () {
    test('iptalden sonra 2 dk: yeni aday SOS başlatmaz, `suppressed`; 2 dk sonra yine tetikler', () {
      fakeAsync((async) {
        build();
        emit(async);
        run(async, const Duration(seconds: 5));
        expect(rig.controller.cancel(SosCancelSource.voice), isTrue);
        expect(actNames(), [FallAct.started, FallAct.cancelled]);
        expect(bridge.suppressing, isTrue);

        now = now.add(const Duration(minutes: 1, seconds: 59));
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        expect(actNames().last, FallAct.suppressed);
        expect(rig.outcomes.where((o) => o.$2 == SosOutcome.cancelled), hasLength(1));

        now = now.add(const Duration(seconds: 2)); // toplam > 2 dk
        expect(bridge.suppressing, isFalse);
        emit(async);
        expect(rig.controller.phase, SosPhase.countdown);
        expect(actNames().last, FallAct.started);
        dispose();
      });
    });

    test('bastırma iptal ANINDAN başlar (aday anından değil): 25 sn\'lik geri sayım süresi sayılmaz', () {
      fakeAsync((async) {
        build();
        emit(async);
        run(async, const Duration(seconds: 20)); // geri sayımın 20. sn'si
        rig.controller.cancel(SosCancelSource.glasses);
        // Adaydan bu yana 20 sn + 2 dk - 1 sn geçti ama iptalden yalnızca 1 dk 59 sn.
        now = now.add(const Duration(minutes: 1, seconds: 59));
        emit(async);
        expect(actNames().last, FallAct.suppressed);
        dispose();
      });
    });

    test('iptal edilmeyen (gönderilen) SOS bastırma BAŞLATMAZ', () {
      fakeAsync((async) {
        build();
        emit(async);
        run(async, const Duration(seconds: 50));
        expect(actNames(), [FallAct.started, FallAct.sent]);
        expect(bridge.suppressing, isFalse);
        dispose();
      });
    });

    test('ELLE SOS\'un iptali bastırma başlatmaz; elle SOS\'u bastırma etkilemez', () {
      fakeAsync((async) {
        build();
        rig.controller.trigger(SosSource.voice);
        async.flushMicrotasks();
        rig.controller.cancel(SosCancelSource.voice);
        expect(bridge.suppressing, isFalse, reason: 'elle SOS iptali düşmeyi bastırmaz');

        // Düşme SOS'u iptal edilir -> bastırma; elle SOS yine de başlar.
        emit(async);
        rig.controller.cancel(SosCancelSource.voice);
        expect(bridge.suppressing, isTrue);
        rig.controller.trigger(SosSource.voice);
        async.flushMicrotasks();
        expect(rig.controller.phase, SosPhase.countdown);
        expect(rig.controller.status.value.source, SosSource.voice);
        dispose();
      });
    });

    test('bastırma bellekte: yeni köprü (uygulama yeniden açıldı) bastırmasızdır', () {
      fakeAsync((async) {
        build();
        emit(async);
        rig.controller.cancel(SosCancelSource.voice);
        expect(bridge.suppressing, isTrue);
        bridge.dispose();
        final fresh = FallSosBridge(
          candidates: stream.stream,
          sos: rig.controller,
          mode: () => mode,
          armed: () => armed,
          interruptOrdinary: () async {},
          now: () => now,
        );
        expect(fresh.suppressing, isFalse);
        fresh.dispose();
        rig.dispose();
        stream.close();
      });
    });
  });

  group('süren SOS ve diyalog (karar 8)', () {
    test('geri sayım sürerken yeni aday onu KESMEZ ve ikinci SOS başlatmaz (`suppressed`)', () {
      fakeAsync((async) {
        build();
        emit(async);
        run(async, const Duration(seconds: 10));
        final before = interrupts;
        emit(async);
        expect(rig.controller.phase, SosPhase.countdown, reason: 'geri sayım kesilmedi');
        expect(rig.log.where((e) => e.startsWith('countdown(')).length, 1);
        expect(actNames(), [FallAct.started, FallAct.suppressed]);
        expect(interrupts, before, reason: 'sıradan diyalog da yeniden kesilmez');
        dispose();
      });
    });

    test('elle SOS sürerken gelen aday kesmez, `suppressed`', () {
      fakeAsync((async) {
        build();
        rig.controller.trigger(SosSource.glasses);
        async.flushMicrotasks();
        emit(async);
        expect(rig.controller.status.value.source, SosSource.glasses);
        expect(actNames(), [FallAct.suppressed]);
        dispose();
      });
    });

    test('SOS\'un başlattığı arama sürerken (faz idle olsa da) gelen aday kesmez', () {
      fakeAsync((async) {
        build();
        rig.controller.trigger(SosSource.voice);
        async.flushMicrotasks();
        run(async, const Duration(seconds: 12)); // gönderim bitti, arama sürüyor (40 sn)
        expect(rig.controller.phase, SosPhase.idle);
        expect(rig.controller.callInProgress, isTrue);
        emit(async);
        expect(actNames(), [FallAct.suppressed]);
        expect(rig.controller.phase, SosPhase.idle);
        dispose();
      });
    });

    test('sıradan diyalog/dinleme süriyorsa aday onu keser, sonra geri sayım başlar', () {
      fakeAsync((async) {
        build();
        emit(async);
        expect(interrupts, 1);
        expect(rig.controller.phase, SosPhase.countdown);
        dispose();
      });
    });

    test('kesme sürerken SOS başka yoldan başladıysa aday ikinci SOS başlatmaz', () {
      fakeAsync((async) {
        build();
        final gate = Completer<void>();
        bridge.dispose();
        bridge = FallSosBridge(
          candidates: stream.stream,
          sos: rig.controller,
          mode: () => mode,
          armed: () => armed,
          interruptOrdinary: () => gate.future,
          onAct: (c, a) => acts.add((c, a)),
          now: () => now,
        );
        emit(async);
        rig.controller.trigger(SosSource.glasses); // kesme sürerken elle SOS
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(rig.controller.status.value.source, SosSource.glasses);
        expect(actNames(), [FallAct.suppressed]);
        dispose();
      });
    });

    test('kesme sürerken mod kapanırsa tetiklenmez', () {
      fakeAsync((async) {
        build();
        final gate = Completer<void>();
        bridge.dispose();
        bridge = FallSosBridge(
          candidates: stream.stream,
          sos: rig.controller,
          mode: () => mode,
          armed: () => armed,
          interruptOrdinary: () => gate.future,
          onAct: (c, a) => acts.add((c, a)),
          now: () => now,
        );
        emit(async);
        mode = FallMode.off;
        gate.complete();
        async.flushMicrotasks();
        expect(rig.controller.phase, SosPhase.idle);
        expect(acts, isEmpty);
        dispose();
      });
    });

    test('kesme hata fırlatsa da SOS yine başlar', () {
      fakeAsync((async) {
        build();
        bridge.dispose();
        bridge = FallSosBridge(
          candidates: stream.stream,
          sos: rig.controller,
          mode: () => mode,
          armed: () => armed,
          interruptOrdinary: () async => throw StateError('kesilemedi'),
          onAct: (c, a) => acts.add((c, a)),
          now: () => now,
        );
        emit(async);
        expect(rig.controller.phase, SosPhase.countdown);
        dispose();
      });
    });
  });

  group('ön kontrol ve sınır', () {
    test('acil kişi yoksa ön kontrolde takılır: SOS başlamaz, `suppressed` (112 teklifi SOS\'un işi)', () {
      fakeAsync((async) {
        build();
        rig.store.remove(ayse.key);
        rig.store.remove(ali.key);
        emit(async);
        expect(rig.controller.phase, SosPhase.idle);
        expect(actNames(), [FallAct.suppressed]);
        expect(rig.log.any((e) => e.startsWith('noContacts')), isTrue, reason: 'nedeni söylenir');
        dispose();
      });
    });

    test('60 sn sınırı (başarıyla gönderilmiş SOS sonrası): `suppressed`', () {
      fakeAsync((async) {
        build();
        rig.controller.trigger(SosSource.glasses);
        async.flushMicrotasks();
        run(async, const Duration(seconds: 14)); // 7 sn + gönderim
        expect(rig.controller.phase, SosPhase.idle);
        emit(async);
        expect(actNames(), [FallAct.suppressed]);
        dispose();
      });
    });

    test('gönderim hiçbir kanaldan çıkmazsa etiket `started` kalır (sent yazılmaz)', () {
      fakeAsync((async) {
        build();
        rig.direct.smsResult = SmsSendStatus.failed;
        rig.direct.callSucceeds = false;
        emit(async);
        run(async, const Duration(seconds: 60));
        expect(actNames(), [FallAct.started]);
        dispose();
      });
    });
  });

  group('kaynak kodu kilitleri', () {
    List<String> codeLines(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .toList();

    test('`trigger(SosSource.fall)` yalnızca fall_sos_bridge.dart içinde çağrılır', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path == 'lib/sos/fall_sos_bridge.dart') continue;
        if (codeLines(path).join('\n').contains(RegExp(r'trigger\(\s*SosSource\.fall'))) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty);
      expect(codeLines('lib/sos/fall_sos_bridge.dart').join('\n'), contains('trigger(SosSource.fall)'));
    });

    test('fall_sos_bridge.dart yalnızca lib/sos/ altında; lib/fall/ SOS\'u hâlâ hiç bilmez', () {
      expect(File('lib/sos/fall_sos_bridge.dart').existsSync(), isTrue);
      for (final f in Directory('lib/fall').listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(code.toLowerCase().contains('sos'), isFalse, reason: f.path);
      }
    });

    test('köprü sentetik kaynağı süzer ve iptalde bastırma süresini kullanır', () {
      final code = codeLines('lib/sos/fall_sos_bridge.dart').join('\n');
      expect(code, contains('fallSyntheticSourceId'));
      expect(SosConfig.fallCountdown, const Duration(seconds: 25));
      expect(FallSosBridge.suppressionAfterCancel, const Duration(minutes: 2));
    });
  });
}
