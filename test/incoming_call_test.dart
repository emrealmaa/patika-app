import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/battery/phone_battery.dart';
import 'package:patika_app/platform/call_service.dart';
import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/platform/phone_call_service.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';

import 'fakes.dart';
import 'navigation_fixtures.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// "Gerçek" arama servisinin testteki karşılığı: SimulatedCallService DEĞİL
/// (AppState onu Test Modu sayıp izin akışını atlar).
class FakePhoneCalls implements PatikaCallService {
  final _calls = StreamController<IncomingCall?>.broadcast();
  final _states = StreamController<PhoneCallState>.broadcast();
  PhoneCallState _state = PhoneCallState.idle;
  bool startResult = true;
  bool answerResult = true;
  @override
  bool canAnswer = true;
  int starts = 0;
  int answers = 0;
  int rejects = 0;

  void ring(IncomingCall call) {
    _set(PhoneCallState.ringing);
    _calls.add(call);
  }

  void offhook() {
    _calls.add(null);
    _set(PhoneCallState.offhook);
  }

  void idle() {
    _calls.add(null);
    _set(PhoneCallState.idle);
  }

  void _set(PhoneCallState s) {
    _state = s;
    _states.add(s);
  }

  @override
  Stream<IncomingCall?> get incomingCall => _calls.stream;
  @override
  Stream<PhoneCallState> get callState => _states.stream;
  @override
  PhoneCallState get currentState => _state;
  @override
  Future<bool> start() async {
    starts++;
    return startResult;
  }

  @override
  Future<bool> answer() async {
    answers++;
    if (answerResult) offhook();
    return answerResult;
  }

  @override
  Future<bool> reject() async {
    rejects++;
    idle();
    return true;
  }

  @override
  void dispose() {
    _calls.close();
    _states.close();
  }
}

void main() {
  const ahmet = ContactEntry('1', 'Ahmet Yılmaz', ['0555 000 00 01']);

  group('arayan kimliği', () {
    test('rehberde bulunursa rehberdeki ad', () {
      final c = identifyCaller('ahmet yilmaz', const ContactFound(ahmet));
      expect((c.kind, c.callerName), (CallerKind.named, 'Ahmet Yılmaz'));
    });

    test('numara gibi başlık: bilinmeyen numara, numara taşınmaz', () {
      for (final title in ['0555 000 00 09', '+90 555 000 0009', '(0555) 000-00-09']) {
        final c = identifyCaller(title, null);
        expect(c.kind, CallerKind.unknownNumber, reason: title);
        expect(c.callerName, isEmpty);
      }
    });

    test('rehberde yok: bilinmeyen numara; belirsiz ya da izin yok: arama ekranının adı', () {
      expect(identifyCaller('Olası spam', const ContactNotFound()).kind, CallerKind.unknownNumber);
      expect(identifyCaller('Ahmet', const ContactAmbiguous([ahmet])).callerName, 'Ahmet');
      expect(identifyCaller('Ahmet Yılmaz', null).callerName, 'Ahmet Yılmaz');
      expect(identifyCaller('Ahmet Yılmaz', const ContactPermissionDenied()).kind, CallerKind.named);
    });

    test('bilgi yoksa "bir arama geliyor"', () {
      expect(identifyCaller(null, null).kind, CallerKind.unidentified);
      expect(identifyCaller('  ', null).kind, CallerKind.unidentified);
    });

    test('numara algılama harf içeren adı numara saymaz', () {
      expect(looksLikePhoneNumber('Ali 2'), isFalse);
      expect(looksLikePhoneNumber('112'), isTrue);
      expect(looksLikePhoneNumber('12'), isFalse);
    });
  });

  group('MethodChannelCallService', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/call_state');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final invoked = <String>[];

    setUp(() {
      invoked.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        invoked.add(call.method);
        return switch (call.method) {
          'start' => {'active': true, 'canAnswer': true, 'state': 'idle'},
          'answer' || 'reject' => true,
          _ => null,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    MethodChannelCallService service({ContactMatch? match}) => MethodChannelCallService(
          channel: channel,
          match: (_) async => match,
        );

    test('çalma + arayan bildirimi: ad beklemeden duyurulur', () {
      fakeAsync((async) {
        final s = service(match: const ContactFound(ahmet));
        final calls = <IncomingCall?>[];
        s.incomingCall.listen(calls.add);
        s.start();
        async.flushMicrotasks();
        expect(s.canAnswer, isTrue);
        s.handle(const MethodCall('onState', 'ringing'));
        s.handle(const MethodCall('callerHint', {'name': 'Ahmet Yılmaz'}));
        async.flushMicrotasks();
        expect(calls.single?.callerName, 'Ahmet Yılmaz');
        async.elapse(const Duration(seconds: 2));
        expect(calls, hasLength(1), reason: 'tek duyuru');
        s.dispose();
      });
    });

    test('bildirim gelmezse 1,5 sn sonra "bir arama geliyor"', () {
      fakeAsync((async) {
        final s = service();
        final calls = <IncomingCall?>[];
        s.incomingCall.listen(calls.add);
        s.handle(const MethodCall('onState', 'ringing'));
        async.elapse(const Duration(milliseconds: 1400));
        expect(calls, isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect(calls.single?.kind, CallerKind.unidentified);
        s.dispose();
      });
    });

    test('bildirim çalmadan önce geldiyse hemen; açılınca/bitince null', () {
      fakeAsync((async) {
        final s = service();
        final calls = <IncomingCall?>[];
        final states = <PhoneCallState>[];
        s.incomingCall.listen(calls.add);
        s.callState.listen(states.add);
        s.handle(const MethodCall('callerHint', {'name': '0555 000 00 09'}));
        s.handle(const MethodCall('onState', 'ringing'));
        async.elapse(Duration.zero);
        expect(calls.single?.kind, CallerKind.unknownNumber);
        s.handle(const MethodCall('onState', 'offhook'));
        s.handle(const MethodCall('onState', 'idle'));
        async.flushMicrotasks();
        expect(calls.last, isNull);
        expect(states, [PhoneCallState.ringing, PhoneCallState.offhook, PhoneCallState.idle]);
        s.dispose();
      });
    });

    test('aç/reddet native\'e gider', () async {
      final s = service();
      expect(await s.answer(), isTrue);
      expect(await s.reject(), isTrue);
      expect(invoked, ['answer', 'reject']);
      s.dispose();
    });
  });

  group('uygulamada', () {
    Harness real(FakePhoneCalls calls, {bool permission = true, List<EmergencyContact> sos = const []}) =>
        Harness(
          callService: calls,
          ensurePhoneStatePermission: ({required bool ask}) async => permission,
          direct: sos.isEmpty ? const NoDirectActions() : FakeDirectActions(),
          emergencyContacts: sos,
        );

    test('türüne göre duyuru: ad / bilinmeyen numara / bir arama', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls);
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        h.speakAll(async);
        calls.idle();
        calls.ring(const IncomingCall(callerName: '', kind: CallerKind.unknownNumber));
        h.speakAll(async);
        calls.idle();
        calls.ring(const IncomingCall(callerName: '', kind: CallerKind.unidentified));
        h.speakAll(async);
        expect(h.tts.spoken, [
          'Ahmet Yılmaz arıyor',
          Tr.incomingCallUnknownNumber,
          Tr.incomingCallUnidentified,
        ]);
        h.dispose();
      });
    });

    test('dokunuş açar; görüşme başlayınca TTS susar, pil uyarısı ve mesaj bekler', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls);
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.tap);
        async.flushMicrotasks();
        expect(calls.answers, 1);
        expect(h.app.inPhoneCall, isTrue);
        expect(h.tts.stops, greaterThan(0), reason: 'görüşme başlayınca TTS susar');
        expect(h.speech.listening, isFalse);

        h.tts.spoken.clear();
        h.phoneBattery.reading = const PhoneBatteryReading(14);
        h.app.pollPhoneBattery();
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty, reason: 'görüşmede pil uyarısı konuşmaz');

        calls.idle();
        h.speakAll(async);
        expect(h.tts.spoken, ['Telefon pili yüzde 14'], reason: 'görüşme bitince söylenir');
        h.dispose();
      });
    });

    test('görüşmede gelen mesaj okunmaz ama günlüğe girer', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final messages = FakeIncomingMessages();
        final h = Harness(
          callService: calls,
          ensurePhoneStatePermission: ({required bool ask}) async => true,
          incomingMessages: messages,
        );
        calls.offhook();
        async.flushMicrotasks();
        messages.emit(const IncomingMessage(senderName: "Ayşe Demir", body: "merhaba", appPackage: "com.whatsapp"));
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty);
        h.dispose();
      });
    });

    test('çalarken uzun basış reddeder; çalmıyorken SOS', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls);
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.longPress);
        h.speakAll(async);
        expect(calls.rejects, 1);
        expect(h.tts.spoken.last, 'Ahmet Yılmaz için gelen arama reddedildi');

        h.app.simulator!.injectButton(GlassesButton.longPress);
        h.speakAll(async);
        expect(h.tts.spoken.last, contains('Bu sürümde acil durum mesajı gönderilemiyor'));
        h.dispose();
      });
    });

    test('izin yoksa aç/reddet denenmez, nedeni söylenir', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls()..canAnswer = false;
        final h = real(calls);
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        h.speakAll(async);
        h.app.simulator!.injectButton(GlassesButton.tap);
        h.speakAll(async);
        expect(calls.answers, 0);
        expect(h.tts.spoken.last, Tr.callAnswerUnavailable);
        h.dispose();
      });
    });

    test('SOS geri sayımında gelen arama duyurulmaz, SOS sürer', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls, sos: const [EmergencyContact('Ayşe Demir', '0555 000 00 03')]);
        h.app.simulator!.injectButton(GlassesButton.longPress);
        async.elapse(const Duration(seconds: 1));
        expect(h.app.sos.phase, SosPhase.countdown);
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken, isNot(contains('Ahmet Yılmaz arıyor')));
        expect(h.app.sos.phase, SosPhase.countdown);
        h.app.sos.cancel(SosCancelSource.screen);
        h.speakAll(async);
        h.dispose();
      });
    });

    test('karşıya geçiş duraklamasında arama duyurulur; çift dokunuş yine navigasyonu sürdürür', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls);
        h.app.navigation.start(testRoute());
        async.flushMicrotasks();
        for (final (x, y) in walkPath([(0, 0), (0, 200), (140, 200)])) {
          h.location.emit(enu(x, y));
          async.elapse(const Duration(seconds: 1));
          h.speakAll(async);
        }
        expect(h.app.navigation.isPausedForCrossing, isTrue);
        h.tts.spoken.clear();
        calls.ring(const IncomingCall(callerName: 'Ahmet Yılmaz'));
        h.speakAll(async);
        expect(h.tts.spoken, contains('Ahmet Yılmaz arıyor'));
        h.app.simulator!.injectButton(GlassesButton.doubleTap);
        h.speakAll(async);
        expect(h.app.navigation.isPausedForCrossing, isFalse);
        expect(calls.answers, 0, reason: 'çift dokunuş aramayı açmaz');

        h.dispose();
      });
    });

    test('izin: açılışta sorulmaz; eğitim sonunda istenir, reddedilirse "kısıtlı"', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final asked = <bool>[];
        final h = Harness(
          callService: calls,
          ensurePhoneStatePermission: ({required bool ask}) async {
            asked.add(ask);
            return false;
          },
        );
        h.app.enableCallDetection(ask: false);
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty);
        h.app.enableCallDetection(ask: true);
        h.speakAll(async);
        expect(asked, [false, true]);
        expect(h.tts.spoken, [Tr.callFeaturesLimited]);
        expect(calls.starts, 0);
        h.dispose();
      });
    });

    test('izin verilince izleme başlar; bildirim erişimi yoksa ad için söylenir', () {
      fakeAsync((async) {
        final calls = FakePhoneCalls();
        final h = real(calls);
        h.app.enableCallDetection(ask: true);
        h.speakAll(async);
        expect(calls.starts, 1);
        expect(h.tts.spoken, [Tr.callerNameNeedsNotificationAccess]);
        h.dispose();
      });
    });
  });

  test('strings_tr.dart "Gelen arama" bölümü yasaklı kelime içermez', () {
    final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
    final start = source.indexOf('// --- Gelen arama (Faz 4b)');
    final next = source.indexOf('\n  // --- ', start + 10);
    final section = source.substring(start, next);
    final code = section.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    final literals = RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!);
    // Mesaj uyarısındaki "dikkat edin" bu bölümün eski metni (navigasyon değil);
    // yalnızca arama cümleleri taranır.
    for (final text in literals.where((t) => !t.contains('kalabalık') && !t.contains('Mesaj içerikleri'))) {
      if (text.contains('arama') || text.contains('arıyor') || text.contains('Görüşme') || text.contains('telefon')) {
        expect(bannedIn(text), isEmpty, reason: '"$text"');
      }
    }
  });
}
