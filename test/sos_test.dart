import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/guidance_engine.dart' show PositionFix;
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/emergency_number.dart';
import 'package:patika_app/sos/sos_call_monitor.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';
import 'package:patika_app/sos/sos_delivery.dart';
import 'package:patika_app/sos/sos_message.dart';

import 'fakes.dart';

const ayse = EmergencyContact('Ayşe Demir', '0534 777 88 99');
const ali = EmergencyContact('Ali Kaya', '0533 444 55 66');
const testNumber = '0999 000 00 00';

final fix = PositionFix(const LatLng(41.0, 29.0), 12, DateTime(2026, 9, 28, 14, 5));

/// Sıra kontrolü için: aramalar ve SMS'ler ortak günlüğe yazılır.
class LoggedDirect extends FakeDirectActions {
  final List<String> log;

  /// Bu numaranın SMS'i [held] tamamlanana dek bekler (geç kalan SMS).
  final Map<String, Completer<SmsSendStatus>> held = {};

  LoggedDirect(this.log);

  @override
  Future<bool> call(String number) {
    log.add('call:$number');
    return super.call(number);
  }

  @override
  Future<SmsSendStatus> sendSms(String number, String body) {
    log.add('sms:$number');
    final gate = held[number];
    if (gate != null) {
      sms.add((number, body));
      return gate.future;
    }
    return super.sendSms(number, body);
  }
}

/// Denetleyicinin söylediklerini günlüğe yazar. Konuşma [speech] kadar sürer,
/// böylece "arama konuşma bitmeden başlamaz" sırası sınanabilir.
class RecordingAnnouncer implements SosAnnouncer {
  final List<String> log;
  Duration speech = const Duration(seconds: 2);

  RecordingAnnouncer(this.log);

  static String _r(SosRecipientResult r) =>
      '${r.contact.name.split(' ').first}:${r.pending ? 'pending' : r.status.name}';

  @override
  void unsupported() => log.add('unsupported');

  @override
  void noContacts({required bool offer112}) => log.add('noContacts(offer=$offer112)');

  @override
  void noSmsPermission({required bool offer112}) => log.add('noSmsPermission(offer=$offer112)');

  @override
  void noCallPermission() => log.add('noCallPermission');

  @override
  void rateLimited() => log.add('rateLimited');

  @override
  void countdownStarted(SosSource source, Duration total) =>
      log.add('countdown(${source.name},${total.inSeconds})');

  @override
  void tick(Duration remaining) => log.add('tick(${remaining.inSeconds})');

  @override
  void cancelled(SosCancelSource by) => log.add('cancelled(${by.name})');

  @override
  void cancelTooLate() => log.add('tooLate');

  @override
  void sending(SosLocation location) => log.add('sending(${location.name})');

  @override
  Future<void> smsResults(
    List<SosRecipientResult> results, {
    required SosLocation location,
    required SosCallTarget callTarget,
    required bool offer112,
  }) async {
    final target = callTarget.is112 ? '112' : (callTarget.name ?? '-');
    log.add('smsResults(${results.map(_r).join(',')};call=$target;offer=$offer112)');
    await Future<void>.delayed(speech);
    log.add('smsResults:done');
  }

  @override
  Future<void> calling112() async {
    log.add('calling112');
    await Future<void>.delayed(const Duration(seconds: 1));
    log.add('calling112:done');
  }

  @override
  void call112Failed(SosCallOutcome outcome) => log.add('call112Failed(${outcome.name})');

  @override
  Future<void> afterCall(SosReport report, {required List<SosRecipientResult> late}) async {
    log.add('afterCall(late=${late.map(_r).join(',')};call=${report.call.outcome.name})');
  }

  @override
  void followUp({required bool sent}) => log.add('followUp($sent)');
}

/// Arama sonu: `rig.callLength` sonra `rig.callEnd` döner (değerler test
/// sırasında değiştirilebilsin diye çağrı anında okunur) ve günlüğe yazar.
class RigCallMonitor implements SosCallMonitor {
  final Rig rig;

  RigCallMonitor(this.rig);

  @override
  Future<SosCallEnd> untilCallEnds() async {
    await Future<void>.delayed(rig.callLength);
    rig.log.add('callEnded(${rig.callEnd.name})');
    return rig.callEnd;
  }
}

class Rig {
  final log = <String>[];
  late final LoggedDirect direct = LoggedDirect(log);
  final store = MemoryEmergencyContactStore([ayse, ali]);
  final perms = FakeSosPermissions();
  late final RecordingAnnouncer announcer = RecordingAnnouncer(log);
  bool call112 = false;
  bool locationPermission = true;
  int locationCalls = 0;
  Future<PositionFix?> Function() location = () async => fix;
  Duration callLength = const Duration(seconds: 40);
  SosCallEnd callEnd = SosCallEnd.ended;
  EmergencyNumber emergency = const EmergencyNumber(debugTestNumber: testNumber);
  late final SosController controller;

  Rig() {
    controller = SosController(
      delivery: DirectSosDelivery(
        direct: direct,
        contacts: store,
        permissions: perms,
        emergency: emergency,
      ),
      announcer: announcer,
      getLocation: () {
        locationCalls++;
        return location();
      },
      hasLocationPermission: () async => locationPermission,
      call112Enabled: () => call112,
      callMonitor: RigCallMonitor(this),
      now: () => DateTime(2026, 9, 28, 14, 5),
    );
  }

  int indexOf(String prefix) => log.indexWhere((e) => e.startsWith(prefix));
  List<String> where(String prefix) => log.where((e) => e.startsWith(prefix)).toList();

  void dispose() => controller.dispose();
}

void main() {
  group('EmergencyNumber', () {
    test('release dışında varsayılan olarak gerçek 112 aranamaz', () {
      const number = EmergencyNumber();
      expect(number.dialNumber, isNull);
      expect(number.canDial, isFalse);
    });

    test('yalnızca enjekte edilen test numarası aranır', () {
      expect(const EmergencyNumber(debugTestNumber: testNumber).dialNumber, testNumber);
    });

    test('test numarası olarak "112" verilse bile yok sayılır', () {
      expect(const EmergencyNumber(debugTestNumber: '112').dialNumber, isNull);
      expect(const EmergencyNumber(debugTestNumber: '112').canDial, isFalse);
    });

    test('gerçek 112 sabiti kodda yalnızca emergency_number.dart içinde geçer', () {
      final hits = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (RegExp(r''''112'|"112"''').hasMatch(entity.readAsStringSync())) {
          hits.add(entity.path.replaceAll('\\', '/'));
        }
      }
      // strings_tr.dart yalnızca geçmişte görünen etiket ("112" arandı);
      // gerçek numara dial edilmiyor, o yalnızca emergency_number.dart'ta.
      expect(hits, ['lib/l10n/strings_tr.dart', 'lib/sos/emergency_number.dart']);
    });

    test('testlerin sahte DirectActions\'ı 112\'ye arama ve SMS\'te hata fırlatır', () async {
      final direct = FakeDirectActions();
      expect(() => direct.call('112'), throwsStateError);
      expect(() => direct.call(' 1 1 2 '), throwsStateError);
      expect(() => direct.sendSms('112', 'x'), throwsStateError);
    });
  });

  group('acil kişiler', () {
    test('ekler; aynı numara farklı yazılışla mükerrer sayılır; en çok 3 kişi', () async {
      final store = MemoryEmergencyContactStore();
      expect(await store.add(ayse), EmergencyAddResult.added);
      expect(await store.add(const EmergencyContact('Ayşe', '+90 534 777 88 99')), EmergencyAddResult.duplicate);
      expect(await store.add(ali), EmergencyAddResult.added);
      expect(await store.add(const EmergencyContact('Can', '0535 000 00 01')), EmergencyAddResult.added);
      expect(await store.add(const EmergencyContact('Deniz', '0536 000 00 02')), EmergencyAddResult.full);
      expect((await store.readAll()).map((c) => c.name), ['Ayşe Demir', 'Ali Kaya', 'Can']);
    });

    test('anahtarla siler', () async {
      final store = MemoryEmergencyContactStore([ayse, ali]);
      expect(await store.remove(ayse.key), isTrue);
      expect(await store.remove(ayse.key), isFalse);
      expect((await store.readAll()).single, ali);
    });

    test('json gidiş-dönüş; bozuk kayıt atlanır', () {
      expect(EmergencyContact.fromJson(ayse.toJson()), ayse);
      expect(EmergencyContact.fromJson({'name': 'x'}), isNull);
      expect(EmergencyContact.fromJson('bozuk'), isNull);
      expect(EmergencyContact.fromJson({'name': 'x', 'number': '  '}), isNull);
    });
  });

  group('SosMessage', () {
    test('konumlu: bağlantı, doğruluk, saat', () {
      final text = SosMessage.initial(time: DateTime(2026, 9, 28, 9, 7), fix: fix);
      expect(text, contains('ACİL DURUM'));
      expect(text, contains('saat 09:07'));
      expect(text, contains('https://maps.google.com/?q=41.000000,29.000000'));
      expect(text, contains('yaklaşık 12 metre'));
      expect(text, isNot(contains('iletildi')));
    });

    test('konumsuz: "Konum alınamadı"', () {
      final text = SosMessage.initial(time: DateTime(2026, 9, 28, 9, 7));
      expect(text, contains('Konum alınamadı'));
      expect(text, isNot(contains('maps.google.com')));
    });

    test('takip mesajı güncel konumu taşır', () {
      final text = SosMessage.followUp(time: DateTime(2026, 9, 28, 9, 8), fix: fix);
      expect(text, contains('güncel konum'));
      expect(text, contains('maps.google.com/?q=41.000000,29.000000'));
    });
  });

  group('DirectSosDelivery', () {
    late List<String> log;
    late LoggedDirect direct;
    late FakeSosPermissions perms;
    late MemoryEmergencyContactStore store;

    DirectSosDelivery make({EmergencyNumber emergency = const EmergencyNumber(debugTestNumber: testNumber)}) =>
        DirectSosDelivery(direct: direct, contacts: store, permissions: perms, emergency: emergency);

    setUp(() {
      log = [];
      direct = LoggedDirect(log);
      perms = FakeSosPermissions();
      store = MemoryEmergencyContactStore([ayse, ali]);
    });

    test('ön kontrol: hazır', () async {
      expect(await make().preflight(allow112: false), SosPreflight.ready);
    });

    test('ön kontrol: doğrudan eylem yoksa (play) desteklenmiyor', () async {
      direct.available = false;
      expect(await make().preflight(allow112: false), SosPreflight.unsupported);
    });

    test('ön kontrol: kişi yok / SMS izni yok', () async {
      perms.sms = false;
      expect(await make().preflight(allow112: false), SosPreflight.noSmsPermission);
      perms.sms = true;
      store = MemoryEmergencyContactStore();
      expect(await make().preflight(allow112: false), SosPreflight.noContacts);
    });

    test('ön kontrol: kişi yok ama 112 açık ve aranabiliyorsa hazır (yalnızca arama)', () async {
      store = MemoryEmergencyContactStore();
      expect(await make().preflight(allow112: true), SosPreflight.ready);
      perms.call = false;
      expect(await make().preflight(allow112: true), SosPreflight.noCallPermission);
    });

    test('ön kontrol: 112 açık ama numara kullanılamıyorsa (test numarası yok) kişi yok sayılır', () async {
      store = MemoryEmergencyContactStore();
      expect(await make(emergency: const EmergencyNumber()).preflight(allow112: true), SosPreflight.noContacts);
    });

    test('SMS hepsine aynı metinle gider; aramadan ayrı', () async {
      final batch = await make().startSms(SosRequest(
        source: SosSource.voice,
        time: DateTime(2026, 9, 28, 14, 5),
        fix: fix,
        allow112: false,
      ));
      await batch.settled;
      expect(direct.sms.map((s) => s.$1), [ayse.number, ali.number]);
      expect(direct.sms.map((s) => s.$2).toSet(), hasLength(1));
      expect(direct.sms.first.$2, contains('maps.google.com'));
      expect(batch.results.every((r) => r.sent), isTrue);
      expect(direct.calls, isEmpty);
    });

    test('SMS izni yoksa hiçbir SMS gitmez, sonuç "unavailable"', () async {
      perms.sms = false;
      final batch = await make().startSms(
          SosRequest(source: SosSource.voice, time: DateTime(2026), allow112: false));
      expect(direct.sms, isEmpty);
      expect(batch.results.map((r) => r.status), everyElement(SmsSendStatus.unavailable));
    });

    test('geç kalan SMS "pending" görünür, sonra sonucu gelir', () async {
      final gate = Completer<SmsSendStatus>();
      direct.held[ali.number] = gate;
      final batch = await make().startSms(
          SosRequest(source: SosSource.voice, time: DateTime(2026), allow112: false));
      await Future<void>.delayed(Duration.zero);
      expect(batch.hasPending, isTrue);
      expect(batch.results.map((r) => r.pending), [false, true]);
      expect(batch.results.last.sent, isFalse, reason: 'bekleyen sonuç "gönderildi" sayılmaz');

      gate.complete(SmsSendStatus.failed);
      await batch.settled;
      expect(batch.hasPending, isFalse);
      expect(batch.results.last.status, SmsSendStatus.failed);
    });

    test('tek arama: 112 kapalıysa ilk kişi', () async {
      final d = make();
      expect(await d.plannedCall(allow112: false), isA<SosCallTarget>().having((t) => t.name, 'name', ayse.name));
      final call = await d.placeCall(allow112: false);
      expect(call.placed, isTrue);
      expect(direct.calls, [ayse.number]);
    });

    test('tek arama: 112 açıksa yalnızca enjekte edilen test numarası aranır', () async {
      final call = await make().placeCall(allow112: true);
      expect(call.placed, isTrue);
      expect(call.target.is112, isTrue);
      expect(direct.calls, [testNumber]);
    });

    test('tek arama: release dışında test numarası yoksa arama reddedilir', () async {
      final call = await make(emergency: const EmergencyNumber()).placeCall(allow112: true);
      expect(call.outcome, SosCallOutcome.numberUnavailable);
      expect(direct.calls, isEmpty);
    });

    test('arama izni yoksa noPermission; arama başarısızsa failed', () async {
      perms.call = false;
      expect((await make().placeCall(allow112: false)).outcome, SosCallOutcome.noPermission);
      perms.call = true;
      direct.callSucceeds = false;
      expect((await make().placeCall(allow112: false)).outcome, SosCallOutcome.failed);
    });

    test('kişi yok ve 112 kapalı: aranacak kimse yok', () async {
      store = MemoryEmergencyContactStore();
      expect((await make().placeCall(allow112: false)).outcome, SosCallOutcome.notAttempted);
    });

    test('takip SMS\'i hepsine gider', () async {
      final ok = await make().sendFollowUp(time: DateTime(2026), fix: fix);
      expect(ok, isTrue);
      expect(direct.sms, hasLength(2));
      expect(direct.sms.first.$2, contains('güncel konum'));
    });
  });

  group('SosController', () {
    /// Tetikler ve ön kontrolün bitmesini bekler.
    SosTriggerResult? trigger(Rig rig, FakeAsync async, SosSource source) {
      SosTriggerResult? result;
      rig.controller.trigger(source).then((r) => result = r);
      async.flushMicrotasks();
      return result;
    }

    void run(FakeAsync async, Duration d) {
      async.elapse(d);
      async.flushMicrotasks();
    }

    test('iptal edilmezse GÖNDERİR: 7 sn sonra hepsine SMS, sonra tek arama (ilk kişi)', () {
      fakeAsync((async) {
        final rig = Rig();
        expect(trigger(rig, async, SosSource.voice), SosTriggerResult.started);
        expect(rig.log, ['countdown(voice,7)']);
        expect(rig.controller.phase, SosPhase.countdown);

        run(async, const Duration(seconds: 6));
        expect(rig.direct.sms, isEmpty, reason: 'geri sayım bitmeden gitmez');

        run(async, const Duration(seconds: 1));
        expect(rig.direct.sms.map((s) => s.$1), [ayse.number, ali.number]);

        run(async, const Duration(seconds: 3));
        expect(rig.direct.calls, [ayse.number]);
        expect(rig.controller.phase, SosPhase.idle);
        rig.dispose();
      });
    });

    test('geri sayım her saniye tik verir (6..1)', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.glasses);
        run(async, const Duration(seconds: 7));
        expect(rig.where('tick'), ['tick(6)', 'tick(5)', 'tick(4)', 'tick(3)', 'tick(2)', 'tick(1)']);
        rig.dispose();
      });
    });

    test('SMS sonuçları ARAMA BAŞLAMADAN, konuşma bitince söylenir', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        run(async, const Duration(seconds: 7));
        run(async, const Duration(seconds: 3));

        final spokenStart = rig.indexOf('smsResults(');
        final spokenDone = rig.indexOf('smsResults:done');
        final call = rig.indexOf('call:');
        expect(spokenStart, isNonNegative);
        expect(spokenStart, lessThan(spokenDone));
        expect(spokenDone, lessThan(call), reason: 'arama konuşma bitmeden başlamaz');
        expect(rig.log[spokenStart], contains('Ayşe:sent,Ali:sent'));
        expect(rig.log[spokenStart], contains('call=Ayşe'));
        expect(rig.log[spokenStart], contains('offer=false'));
        rig.dispose();
      });
    });

    test('"dur"a karşılık gelen bir iptal yolu yoktur; iptal yalnızca cancel()', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        run(async, const Duration(seconds: 3));
        expect(rig.controller.cancel(SosCancelSource.glasses), isTrue);
        expect(rig.log, contains('cancelled(glasses)'));
        expect(rig.controller.phase, SosPhase.idle);

        run(async, const Duration(minutes: 5));
        expect(rig.direct.sms, isEmpty);
        expect(rig.direct.calls, isEmpty);
        rig.dispose();
      });
    });

    test('gönderim başladıktan sonra iptal edilemez', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        run(async, const Duration(seconds: 7));
        expect(rig.controller.phase, SosPhase.sending);

        expect(rig.controller.cancel(SosCancelSource.voice), isFalse);
        expect(rig.log, contains('tooLate'));
        run(async, const Duration(seconds: 3));
        expect(rig.direct.calls, [ayse.number]);
        rig.dispose();
      });
    });

    test('geri sayımdayken ikinci tetikleme yok sayılır', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.alreadyRunning);
        expect(rig.where('countdown'), hasLength(1));
        rig.dispose();
      });
    });

    test('sendNow geri sayımı beklemeden gönderir (koruma süresinden sonra)', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        run(async, const Duration(seconds: 2));
        expect(rig.controller.sendNow(), isTrue);
        run(async, const Duration(seconds: 3));
        expect(rig.direct.sms, hasLength(2));
        rig.dispose();
      });
    });

    test('sendNow koruması: ilk 2 sn içinde gelen "yardım" tekrarı SAYILMAZ (tanıyıcı yinelemesi)', () {
      fakeAsync((async) {
        final rig = Rig();
        trigger(rig, async, SosSource.voice);
        run(async, const Duration(milliseconds: 500));
        expect(rig.controller.sendNow(), isFalse,
            reason: 'tetikleyici cümlenin yinelenmiş sonucu iptal penceresini kaybettirmemeli');
        expect(rig.controller.phase, SosPhase.countdown, reason: 'geri sayım sürmeye devam eder');
        expect(rig.direct.sms, isEmpty);

        run(async, const Duration(seconds: 7));
        expect(rig.direct.sms, hasLength(2), reason: 'geri sayım kendi süresinde normal bitti');
        rig.dispose();
      });
    });

    group('geçmiş: yalnızca isim ve sonuç durumu (telefon numarası/konum YAZILMAZ)', () {
      test('normal gönderim', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 12));

          expect(rig.controller.history, isNotEmpty);
          final text = rig.controller.history.map((e) => e.text).join('\n');
          expect(text, contains('Ayşe Demir'), reason: 'aranan kişinin adı geçer');
          expect(text, isNot(contains(ayse.number)));
          expect(text, isNot(contains(ali.number)));
          expect(text, isNot(contains('41.')), reason: 'enlem/boylam yazılmamalı');
          expect(text, isNot(contains('maps.google.com')), reason: 'konum bağlantısı yazılmamalı');
          expect(text, isNot(contains(fix.accuracyMeters.toString())));
          rig.dispose();
        });
      });

      test('112 aranınca yalnızca "112" etiketi geçer, gerçek numara/test numarası değil', () {
        fakeAsync((async) {
          final rig = Rig()..call112 = true;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 12));
          final text = rig.controller.history.map((e) => e.text).join('\n');
          expect(text, contains('112'));
          expect(text, isNot(contains(testNumber)));
          rig.dispose();
        });
      });

      test('geçmiş en fazla maxHistory satır tutar', () {
        fakeAsync((async) {
          final rig = Rig();
          for (var i = 0; i < SosController.maxHistory + 5; i++) {
            trigger(rig, async, SosSource.voice);
            run(async, const Duration(seconds: 12));
            run(async, const Duration(minutes: 2)); // 60 sn sınırını aş
          }
          expect(rig.controller.history.length, SosController.maxHistory);
          rig.dispose();
        });
      });
    });

    group('60 sn sınırı', () {
      /// Başarıyla çıkan bir SOS'u bitirir.
      void sendOne(Rig rig, FakeAsync async, SosSource source) {
        trigger(rig, async, source);
        run(async, const Duration(seconds: 12));
      }

      test('başarıyla giden SOS\'tan sonra sesli olmayan tetikleyici engellenir; sesli "yardım" engellenmez', () {
        fakeAsync((async) {
          final rig = Rig();
          sendOne(rig, async, SosSource.voice);
          expect(rig.controller.phase, SosPhase.idle);

          expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.rateLimited);
          expect(rig.log, contains('rateLimited'));

          expect(trigger(rig, async, SosSource.voice), SosTriggerResult.started);
          rig.controller.cancel(SosCancelSource.voice);

          run(async, const Duration(seconds: 61));
          expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.started);
          rig.dispose();
        });
      });

      test('iptal edilen SOS sınırı SAYMAZ', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.glasses);
          rig.controller.cancel(SosCancelSource.screen);
          expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.started);
          rig.dispose();
        });
      });

      test('gönderilemeyen SOS sınırı SAYMAZ', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.direct
            ..smsResult = SmsSendStatus.failed
            ..callSucceeds = false;
          trigger(rig, async, SosSource.glasses);
          run(async, const Duration(seconds: 20));
          expect(rig.controller.phase, SosPhase.idle);
          expect(rig.direct.sms, isNotEmpty);

          expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.started);
          rig.dispose();
        });
      });
    });

    group('konum', () {
      test('konum geri sayım BAŞLARKEN aranır; SMS\'e girer', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.voice);
          expect(rig.locationCalls, 1, reason: 'geri sayım bitmeden istenmiş olmalı');
          run(async, const Duration(seconds: 7));
          expect(rig.log, contains('sending(included)'));
          expect(rig.direct.sms.first.$2, contains('maps.google.com/?q=41.000000,29.000000'));
          rig.dispose();
        });
      });

      test('geç gelen konum için en fazla 3 sn beklenir ve kullanılır', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.location = () => Future.delayed(const Duration(seconds: 9), () => fix);
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 8)); // geri sayım bitti, konum 9. sn'de
          expect(rig.direct.sms, isEmpty, reason: 'konum için bekleniyor');
          run(async, const Duration(seconds: 2));
          expect(rig.log, contains('sending(included)'));
          expect(rig.direct.sms.first.$2, contains('maps.google.com'));
          rig.dispose();
        });
      });

      test('3 sn içinde gelmezse konumsuz gider ve TEK takip SMS\'i atılır', () {
        fakeAsync((async) {
          final rig = Rig();
          var attempt = 0;
          rig.location = () {
            attempt++;
            return attempt == 1
                ? Completer<PositionFix?>().future // hiç gelmez
                : Future.value(fix);
          };
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 11)); // 7 + 3 grace + 1
          expect(rig.log, contains('sending(unavailable)'));
          expect(rig.direct.sms.first.$2, contains('Konum alınamadı'));
          final firstRound = rig.direct.sms.length;
          expect(firstRound, 2);

          run(async, const Duration(minutes: 5));
          expect(rig.direct.sms.length, firstRound + 2, reason: 'her kişiye bir takip SMS\'i, bir kez');
          expect(rig.direct.sms.last.$2, contains('güncel konum'));
          expect(rig.where('followUp'), ['followUp(true)']);
          rig.dispose();
        });
      });

      test('konum hiç gelmezse takip SMS\'i yalnızca sınırlı sayıda denenir', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.location = () async => null;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(minutes: 10));
          expect(rig.locationCalls, 1 + SosConfig.followUpAttempts);
          expect(rig.direct.sms, hasLength(2), reason: 'takip SMS\'i yok');
          expect(rig.where('followUp'), isEmpty);
          rig.dispose();
        });
      });

      test('konum izni yoksa konum hiç istenmez, konumsuz gider ve nedeni söylenir', () {
        fakeAsync((async) {
          final rig = Rig()..locationPermission = false;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(minutes: 10));
          expect(rig.locationCalls, 0);
          expect(rig.log, contains('sending(noPermission)'));
          expect(rig.direct.sms, hasLength(2), reason: 'takip SMS\'i de yok');
          expect(rig.direct.sms.first.$2, contains('Konum alınamadı'));
          rig.dispose();
        });
      });
    });

    group('112', () {
      test('ayar kapalıyken ilk kişi aranır', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 12));
          expect(rig.direct.calls, [ayse.number]);
          rig.dispose();
        });
      });

      test('ayar açıksa yalnızca 112 aranır (testte enjekte edilen numara); kişi aranmaz', () {
        fakeAsync((async) {
          final rig = Rig()..call112 = true;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 12));
          expect(rig.direct.calls, [testNumber]);
          expect(rig.where('smsResults('), [contains('call=112')]);
          expect(rig.direct.sms, hasLength(2), reason: 'SMS yine hepsine');
          rig.dispose();
        });
      });

      test('düşme kaynaklı SOS: 112 ayarı açık olsa da KENDİLİĞİNDEN aranmaz; 25 sn geri sayım', () {
        fakeAsync((async) {
          final rig = Rig()..call112 = true;
          trigger(rig, async, SosSource.fall);
          expect(rig.log, ['countdown(fall,25)']);
          run(async, const Duration(seconds: 24));
          expect(rig.direct.sms, isEmpty);
          run(async, const Duration(seconds: 40));
          expect(rig.direct.calls, [ayse.number], reason: 'onay yoksa yalnızca ilk kişi');
          expect(rig.direct.calls, isNot(contains(testNumber)));
          rig.dispose();
        });
      });

      test('düşmede SMS\'lerden sonra kısa pencerede 112 teklifi sunulur; çift dokunuş onaydır', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.fall);
          run(async, const Duration(seconds: 25)); // SMS'ler gitti, sonuçlar söyleniyor
          expect(rig.where('smsResults('), [contains('offer=true')]);
          run(async, const Duration(seconds: 2)); // konuşma bitti, karar penceresi açık
          expect(rig.controller.offering112, isTrue);
          expect(rig.direct.calls, isEmpty, reason: 'pencere sürerken kişi aranmaz');

          SosCallOutcome? outcome;
          rig.controller.confirm112().then((o) => outcome = o);
          run(async, const Duration(seconds: 2));

          expect(outcome, SosCallOutcome.placed);
          expect(rig.direct.calls, [testNumber], reason: 'onaylanınca kişi aranmaz, yalnızca 112');
          expect(rig.indexOf('calling112:done'), lessThan(rig.indexOf('call:')),
              reason: '"112 aranıyor" söylendikten sonra aranır');
          expect(rig.controller.offering112, isFalse);
          rig.dispose();
        });
      });

      test('düşmede pencere onaysız geçerse ilk kişi aranır ve teklif kapanır', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.fall);
          run(async, const Duration(seconds: 25 + 2));
          expect(rig.controller.offering112, isTrue);
          run(async, SosConfig.offerDecisionWindow + const Duration(seconds: 1));
          expect(rig.direct.calls, [ayse.number]);
          expect(rig.controller.offering112, isFalse);
          Object? late = 'bekliyor';
          rig.controller.confirm112().then((o) => late = o);
          async.flushMicrotasks();
          expect(late, isNull, reason: 'teklif kapandı: çift dokunuş 112 onayı sayılmaz');
          rig.dispose();
        });
      });

      test('elle SOS\'ta SMS gittiyse teklif yok ve arama hemen başlar', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.glasses);
          run(async, const Duration(seconds: 7 + 2));
          expect(rig.controller.offering112, isFalse);
          expect(rig.direct.calls, [ayse.number]);
          rig.dispose();
        });
      });

      test('SMS\'lerin hiçbiri gitmediyse: sonuç söylenir, "112" teklif edilir; sınır sayılmaz', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.direct.smsResult = SmsSendStatus.failed;
          trigger(rig, async, SosSource.glasses);
          run(async, const Duration(seconds: 7 + 2));
          expect(rig.where('smsResults('), [allOf(contains('Ayşe:failed'), contains('offer=true'))]);
          expect(rig.controller.offering112, isTrue);
          rig.dispose();
        });
      });

      test('ön kontrolde kişi yoksa: "Acil kişi yok" + 112 teklifi (20 sn); çift dokunuş aramayı onaylar', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.store.remove(ayse.key);
          rig.store.remove(ali.key);
          expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.blocked);
          expect(rig.log, ['noContacts(offer=true)']);
          expect(rig.controller.offering112, isTrue);
          expect(rig.controller.phase, SosPhase.idle);

          rig.controller.confirm112();
          run(async, const Duration(seconds: 3));
          expect(rig.direct.calls, [testNumber]);
          rig.dispose();
        });
      });

      test('teklif 20 sn sonra kapanır; çift dokunuş başka işe yorulabilsin diye null döner', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.store.remove(ayse.key);
          rig.store.remove(ali.key);
          trigger(rig, async, SosSource.voice);
          run(async, SosConfig.offer112Window + const Duration(seconds: 1));
          expect(rig.controller.offering112, isFalse);
          Object? result = 'bekliyor';
          rig.controller.confirm112().then((o) => result = o);
          async.flushMicrotasks();
          expect(result, isNull);
          expect(rig.direct.calls, isEmpty);
          rig.dispose();
        });
      });

      test('SMS izni yoksa sessiz kalmaz: nedeni söylenir ve 112 teklif edilir', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.perms.sms = false;
          expect(trigger(rig, async, SosSource.voice), SosTriggerResult.blocked);
          expect(rig.log, ['noSmsPermission(offer=true)']);
          expect(rig.controller.offering112, isTrue);
          rig.dispose();
        });
      });

      test('aranamayan 112 (release dışı, test numarası yok) sessiz kalmaz', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.store.remove(ayse.key);
          rig.store.remove(ali.key);
          final delivery = DirectSosDelivery(
            direct: rig.direct,
            contacts: rig.store,
            permissions: rig.perms,
          );
          final c = SosController(
            delivery: delivery,
            announcer: rig.announcer,
            getLocation: () async => fix,
            hasLocationPermission: () async => true,
            call112Enabled: () => false,
            callMonitor: FakeCallMonitor(),
          );
          trigger2(c, async);
          async.flushMicrotasks();
          c.confirm112();
          run(async, const Duration(seconds: 3));
          expect(rig.log, contains('call112Failed(numberUnavailable)'));
          expect(rig.direct.calls, isEmpty);
          c.dispose();
          rig.dispose();
        });
      });
    });

    test('desteklenmeyen sürümde (play) geri sayım başlamaz; hemen söylenir', () {
      fakeAsync((async) {
        final rig = Rig();
        rig.direct.available = false;
        expect(trigger(rig, async, SosSource.glasses), SosTriggerResult.blocked);
        expect(rig.log, ['unsupported']);
        expect(rig.controller.phase, SosPhase.idle);
        expect(rig.controller.offering112, isFalse);
        run(async, const Duration(minutes: 1));
        expect(rig.direct.sms, isEmpty);
        rig.dispose();
      });
    });

    group('arama sırasında konuşma yok', () {
      test('geç kalan SMS sonucu arama BİTTİKTEN sonra özetlenir', () {
        fakeAsync((async) {
          final rig = Rig();
          final gate = Completer<SmsSendStatus>();
          rig.direct.held[ali.number] = gate;
          trigger(rig, async, SosSource.voice);

          // 7 sn geri sayım + 10 sn SMS bekleme: Ali'nin sonucu hâlâ yok.
          run(async, const Duration(seconds: 7 + 10));
          run(async, const Duration(seconds: 3));
          expect(rig.where('smsResults('), [allOf(contains('Ayşe:sent'), contains('Ali:pending'))]);
          final callAt = rig.indexOf('call:');
          expect(callAt, isNonNegative);

          // Arama sürerken SMS başarısız olur: hiçbir konuşma olmaz.
          final before = rig.log.length;
          gate.complete(SmsSendStatus.failed);
          run(async, const Duration(seconds: 20));
          expect(rig.log.sublist(before), isEmpty, reason: 'arama sürerken uygulama konuşmaz');

          // Arama biter: özet konuşulur.
          run(async, const Duration(seconds: 30));
          final ended = rig.indexOf('callEnded');
          final summary = rig.indexOf('afterCall(');
          expect(ended, isNonNegative);
          expect(summary, greaterThan(ended));
          expect(rig.log[summary], contains('late=Ali:failed'));
          rig.dispose();
        });
      });

      test('her şey yolundaysa arama sonrası özet konuşulmaz', () {
        fakeAsync((async) {
          final rig = Rig();
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(minutes: 5));
          expect(rig.where('afterCall'), isEmpty);
          rig.dispose();
        });
      });

      test('arama başarısızsa hemen (bekletmeden) söylenir', () {
        fakeAsync((async) {
          final rig = Rig();
          rig.direct.callSucceeds = false;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 12));
          expect(rig.where('afterCall'), [contains('call=failed')]);
          rig.dispose();
        });
      });

      test('aramanın bittiği doğrulanamazsa (unknown) geç kalan SMS özeti HİÇ konuşulmaz', () {
        fakeAsync((async) {
          final rig = Rig()..callEnd = SosCallEnd.unknown;
          final gate = Completer<SmsSendStatus>();
          rig.direct.held[ali.number] = gate;
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 7 + 10 + 3));
          gate.complete(SmsSendStatus.failed);

          run(async, const Duration(minutes: 10));
          expect(rig.where('afterCall'), isEmpty,
              reason: '112 (ya da acil kişi) görüşmesinin üstüne asla konuşulmaz');
          expect(rig.where('callEnded'), ['callEnded(unknown)']);
          rig.dispose();
        });
      });

      test('aramanın bittiği doğrulanamazsa takip SMS\'i duyurusu da konuşulmaz', () {
        fakeAsync((async) {
          final rig = Rig()..callEnd = SosCallEnd.unknown;
          var attempt = 0;
          rig.location = () {
            attempt++;
            return attempt == 1 ? Completer<PositionFix?>().future : Future.value(fix);
          };
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(minutes: 10));
          expect(rig.direct.sms.last.$2, contains('güncel konum'), reason: 'mesaj yine de gider');
          expect(rig.where('followUp'), isEmpty, reason: 'bitiş bilinmiyorsa duyuru hiç yapılmaz');
          rig.dispose();
        });
      });

      test('takip SMS\'inin duyurusu arama sürerken bekler', () {
        fakeAsync((async) {
          final rig = Rig()..callLength = const Duration(seconds: 120);
          var attempt = 0;
          rig.location = () {
            attempt++;
            return attempt == 1 ? Completer<PositionFix?>().future : Future.value(fix);
          };
          trigger(rig, async, SosSource.voice);
          run(async, const Duration(seconds: 48)); // arama başladı, takip SMS'i gitti
          expect(rig.direct.sms.last.$2, contains('güncel konum'));
          expect(rig.where('followUp'), isEmpty, reason: 'arama sürerken söylenmez');
          run(async, const Duration(seconds: 120));
          expect(rig.where('followUp'), ['followUp(true)']);
          expect(rig.indexOf('followUp'), greaterThan(rig.indexOf('callEnded')));
          rig.dispose();
        });
      });
    });

    test('geri sayım süreleri: elle 7 sn, düşme 25 sn', () {
      expect(SosConfig.countdownFor(SosSource.voice), const Duration(seconds: 7));
      expect(SosConfig.countdownFor(SosSource.glasses), const Duration(seconds: 7));
      expect(SosConfig.countdownFor(SosSource.fall), const Duration(seconds: 25));
    });
  });
}

/// `Rig` dışı denetleyiciyi tetiklemek için.
void trigger2(SosController c, FakeAsync async) {
  c.trigger(SosSource.glasses);
  async.flushMicrotasks();
}
