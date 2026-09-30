import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_consent_store.dart';
import 'package:patika_app/fall/fall_enable_session.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_open_gate.dart';
import 'package:patika_app/fall/fall_open_state.dart';

/// Faz 7c-2, adım 2: açık moda iki adımlı geçişin çekirdeği. EN ÖNEMLİ
/// özellik: hiçbir belirsizlik (sessizlik, süre, yanlış kanal, bozulan kapı)
/// açık modu açmaz; tek adımda açılamaz.
void main() {
  const voice = FallEnableChannel.voice;
  const screen = FallEnableChannel.screen;

  late MemoryFallOpenState state;
  late MemoryFallConsentStore consent;
  late FallMode mode;
  late List<FallMode> setCalls;
  late int contacts;
  late bool sms;
  late bool direct;
  late DateTime now;
  late DateTime? since;
  late FallEnableSession session;

  FallEnableSession build({ShadowGatePolicy policy = const ShadowGatePolicy()}) => FallEnableSession(
        gate: FallOpenModeGate(
          directBuild: () async => direct,
          contactCount: () async => contacts,
          hasSmsPermission: () async => sms,
          shadowSince: () async => since,
          policy: policy,
          now: () => now,
        ),
        state: state,
        consent: consent,
        currentMode: () => mode,
        setMode: (m) async {
          setCalls.add(m);
          mode = m;
        },
      );

  setUp(() {
    state = MemoryFallOpenState();
    consent = MemoryFallConsentStore();
    mode = FallMode.shadow;
    setCalls = [];
    contacts = 1;
    sms = true;
    direct = true;
    now = DateTime(2026, 10, 10, 12);
    since = now.subtract(const Duration(days: 8));
    session = build();
  });

  group('iki adım', () {
    test('adım 1 modu AÇMAZ; adım 2 açar', () async {
      final begin = await session.begin(voice);
      expect(begin.kind, FallEnableBeginKind.prompt);
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(session.pending, isTrue);

      final confirm = await session.confirm(voice);
      expect(confirm.kind, FallEnableConfirmKind.enabled);
      expect(mode, FallMode.on);
      expect(setCalls, [FallMode.on]);
      expect(session.pending, isFalse);
    });

    test('tek adımda açılamaz: adım 1 olmadan onay hiçbir şey yapmaz', () async {
      final confirm = await session.confirm(voice);
      expect(confirm.kind, FallEnableConfirmKind.noPending);
      expect(setCalls, isEmpty);
      expect(await state.fullTextHeard(), isFalse);
    });

    test('onaydan sonra ikinci onay sayılmaz (bekleyen yok)', () async {
      await session.begin(voice);
      await session.confirm(voice);
      expect((await session.confirm(voice)).kind, FallEnableConfirmKind.noPending);
      expect(setCalls, [FallMode.on]);
    });

    test('zaten açıksa adım 1 bekleyen kurmaz', () async {
      mode = FallMode.on;
      final begin = await session.begin(voice);
      expect(begin.kind, FallEnableBeginKind.alreadyOn);
      expect(session.pending, isFalse);
    });

    test('kapalı moddan da başlatılabilir ama gölge süresi kapısı aynı (süre yoksa engel)', () async {
      mode = FallMode.off;
      since = null;
      final begin = await session.begin(voice);
      expect(begin.kind, FallEnableBeginKind.blocked);
      expect(begin.gate!.block, FallOpenBlock.shadowTooShort);
    });
  });

  group('bu cihazdaki onay kaydı (yedekten gelmez)', () {
    test('onayda kayıt MOD AÇILMADAN yazılır', () async {
      final order = <String>[];
      final tracking = _OrderConsent(order, consent);
      final s = FallEnableSession(
        gate: FallOpenModeGate(
          directBuild: () async => direct,
          contactCount: () async => contacts,
          hasSmsPermission: () async => sms,
          shadowSince: () async => since,
          now: () => now,
        ),
        state: state,
        consent: tracking,
        currentMode: () => mode,
        setMode: (m) async {
          order.add('mode:${m.name}');
          mode = m;
        },
      );
      await s.begin(voice);
      await s.confirm(voice);
      expect(order, ['grant', 'mode:on']);
      expect(consent.value, isTrue);
    });

    test('kayıt yazılamazsa AÇILMAZ: storageFailed, mod gölge, bayrak yazılmaz, bekleyen temiz', () async {
      consent.failGrant = true;
      await session.begin(voice);
      final c = await session.confirm(voice);
      expect(c.kind, FallEnableConfirmKind.storageFailed);
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(state.heard, isFalse);
      expect(session.pending, isFalse);
    });

    test('adım 1, vazgeç, yanlış kanal, kapı bozulması: onay KAYDEDİLMEZ', () async {
      await session.begin(voice);
      expect(consent.value, isFalse, reason: 'adım 1 yalnızca uyarı');
      await session.confirm(screen);
      expect(consent.value, isFalse, reason: 'yanlış kanal');
      contacts = 0;
      await session.confirm(voice);
      expect(consent.value, isFalse, reason: 'kapı bozuldu');
      contacts = 1;
      await session.begin(voice);
      session.cancel();
      expect(consent.value, isFalse, reason: 'vazgeçildi');
    });
  });

  group('kapılar', () {
    test('adım 1\'de kapı tutmazsa bekleyen kurulmaz, neden döner', () async {
      contacts = 0;
      final begin = await session.begin(screen);
      expect(begin.kind, FallEnableBeginKind.blocked);
      expect(begin.gate!.block, FallOpenBlock.noContacts);
      expect(session.pending, isFalse);
      expect((await session.confirm(screen)).kind, FallEnableConfirmKind.noPending);
      expect(setCalls, isEmpty);
    });

    test('onay anında kapı yeniden denetlenir: acil kişi silinmişse açılmaz, bayrak yazılmaz', () async {
      await session.begin(voice);
      contacts = 0; // uyarı okunurken kişi silindi
      final confirm = await session.confirm(voice);
      expect(confirm.kind, FallEnableConfirmKind.blocked);
      expect(confirm.gate!.block, FallOpenBlock.noContacts);
      expect(mode, FallMode.shadow);
      expect(setCalls, isEmpty);
      expect(await state.fullTextHeard(), isFalse);
      expect(session.pending, isFalse);
    });

    test('onay anında SMS izni geri alınmışsa açılmaz', () async {
      await session.begin(screen);
      sms = false;
      final confirm = await session.confirm(screen);
      expect(confirm.kind, FallEnableConfirmKind.blocked);
      expect(setCalls, isEmpty);
    });
  });

  group('kanal kilidi', () {
    test('sesle başlayan açma ekrandan onaylanamaz; bekleyen sürer', () async {
      await session.begin(voice);
      final wrong = await session.confirm(screen);
      expect(wrong.kind, FallEnableConfirmKind.wrongChannel);
      expect(setCalls, isEmpty);
      expect(session.pending, isTrue);
      expect(session.pendingChannel, voice);
      expect((await session.confirm(voice)).kind, FallEnableConfirmKind.enabled);
    });

    test('ekranla başlayan açma sesle onaylanamaz', () async {
      await session.begin(screen);
      expect((await session.confirm(voice)).kind, FallEnableConfirmKind.wrongChannel);
      expect(setCalls, isEmpty);
    });

    test('başka kanaldan yeni başlatma öncekini geçersiz kılar', () async {
      await session.begin(voice);
      await session.begin(screen);
      expect(session.pendingChannel, screen);
      expect((await session.confirm(voice)).kind, FallEnableConfirmKind.wrongChannel);
      expect((await session.confirm(screen)).kind, FallEnableConfirmKind.enabled);
    });
  });

  group('zaman aşımı', () {
    test('119 sn: geçerli; 120 sn: süresi doldu, açmaz, bir kez "expired" söyler', () {
      fakeAsync((async) {
        session.begin(voice);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 119));
        expect(session.pending, isTrue);

        async.elapse(const Duration(seconds: 1));
        expect(session.pending, isFalse);

        FallEnableConfirm? first;
        FallEnableConfirm? second;
        session.confirm(voice).then((c) => first = c);
        async.flushMicrotasks();
        session.confirm(voice).then((c) => second = c);
        async.flushMicrotasks();
        expect(first!.kind, FallEnableConfirmKind.expired);
        expect(second!.kind, FallEnableConfirmKind.noPending);
        expect(setCalls, isEmpty);
      });
    });

    test('yeniden başlatma süreyi sıfırlar ve eski süre dolumu yeni açmayı bozmaz', () {
      fakeAsync((async) {
        session.begin(voice);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 100));
        session.begin(voice);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 100)); // ilkine göre 200 sn, ikinciye göre 100
        expect(session.pending, isTrue);

        FallEnableConfirm? c;
        session.confirm(voice).then((v) => c = v);
        async.flushMicrotasks();
        expect(c!.kind, FallEnableConfirmKind.enabled);
      });
    });

    test('onay anındaki kapı denetimi sürerken süre dolarsa açılmaz', () {
      fakeAsync((async) {
        var calls = 0;
        final slow = Completer<bool>();
        final s = FallEnableSession(
          gate: FallOpenModeGate(
            // İlk denetim (adım 1) hemen; ikincisi (onay) yavaş.
            directBuild: () => ++calls == 1 ? Future.value(true) : slow.future,
            contactCount: () async => contacts,
            hasSmsPermission: () async => sms,
            shadowSince: () async => since,
            now: () => now,
          ),
          state: state,
          consent: MemoryFallConsentStore(),
          currentMode: () => mode,
          setMode: (m) async => setCalls.add(m),
        );
        s.begin(voice);
        async.flushMicrotasks();
        expect(s.pending, isTrue);

        FallEnableConfirm? result;
        s.confirm(voice).then((c) => result = c);
        async.flushMicrotasks();
        async.elapse(FallEnableSession.timeout); // denetim sürerken süre doldu
        slow.complete(true);
        async.flushMicrotasks();

        expect(result!.kind, FallEnableConfirmKind.expired);
        expect(setCalls, isEmpty);
        expect(state.heard, isFalse);
      });
    });
  });

  group('tam metin bayrağı (karar 3)', () {
    test('ilk seferde tam metin; bayrak yalnızca onayda yazılır', () async {
      final begin = await session.begin(voice);
      expect(begin.fullText, isTrue);
      expect(await state.fullTextHeard(), isFalse, reason: 'duyurulmak yetmez, onay şart');
      await session.confirm(voice);
      expect(await state.fullTextHeard(), isTrue);
    });

    test('tam metni duyup vazgeçen bir sonraki denemede yine TAM metni duyar', () async {
      expect((await session.begin(voice)).fullText, isTrue);
      session.cancel();
      expect(session.pending, isFalse);
      expect(await state.fullTextHeard(), isFalse);
      expect((await session.begin(voice)).fullText, isTrue);
    });

    test('süresi dolan açma bayrağı yazmaz', () {
      fakeAsync((async) {
        session.begin(voice);
        async.flushMicrotasks();
        async.elapse(FallEnableSession.timeout);
        expect(state.heard, isFalse);
      });
    });

    test('onaydan sonra (kapatıp yeniden açınca) kısa hatırlatma', () async {
      await session.begin(voice);
      await session.confirm(voice);
      await session.closeOpenMode();
      final again = await session.begin(screen);
      expect(again.kind, FallEnableBeginKind.prompt);
      expect(again.fullText, isFalse);
      // Kısa hatırlatmada da iki adım geçerli:
      expect(mode, FallMode.shadow);
      expect((await session.confirm(screen)).kind, FallEnableConfirmKind.enabled);
    });

    test('bayrak ayarlardan bağımsız: oturum yeniden kurulsa da kalıcı durumdan okur', () async {
      await session.begin(voice);
      await session.confirm(voice);
      mode = FallMode.shadow;
      final fresh = build();
      expect((await fresh.begin(voice)).fullText, isFalse);
    });
  });

  group('iptal ve kapatma', () {
    test('cancel bekleyeni bırakır; ardından onay açmaz', () async {
      await session.begin(screen);
      session.cancel();
      expect((await session.confirm(screen)).kind, FallEnableConfirmKind.noPending);
      expect(setCalls, isEmpty);
    });

    test('kapı denetimi sürerken cancel: eski başlatma bekleyen KURMAZ', () async {
      final slow = Completer<bool>();
      final s = FallEnableSession(
        gate: FallOpenModeGate(
          directBuild: () => slow.future,
          contactCount: () async => contacts,
          hasSmsPermission: () async => sms,
          shadowSince: () async => since,
          now: () => now,
        ),
        state: state,
        consent: MemoryFallConsentStore(),
        currentMode: () => mode,
        setMode: (m) async => setCalls.add(m),
      );
      final pending = s.begin(voice);
      await pumpEventQueue();
      s.cancel();
      slow.complete(true);
      final result = await pending;
      expect(result.kind, FallEnableBeginKind.superseded);
      expect(s.pending, isFalse);
      expect((await s.confirm(voice)).kind, FallEnableConfirmKind.noPending);
      expect(setCalls, isEmpty);
    });

    test('kapatma tek adım: açıktan gölgeye, bekleyen de iptal', () async {
      mode = FallMode.on;
      expect(await session.closeOpenMode(), isTrue);
      expect(mode, FallMode.shadow);
      expect(setCalls, [FallMode.shadow]);
    });

    test('açık değilken kapatma zararsız: false, hiçbir şey değişmez', () async {
      expect(await session.closeOpenMode(), isFalse);
      expect(setCalls, isEmpty);
    });

    test('kapatma bekleyen açmayı da iptal eder', () async {
      await session.begin(voice);
      await session.closeOpenMode();
      expect(session.pending, isFalse);
    });
  });

  group('debug 7 gün atlaması izi', () {
    test('atlandıysa hem adım 1 hem onay sonucu bunu taşır', () async {
      since = null;
      session = build(policy: const ShadowGatePolicy(debugSkip: true));
      final begin = await session.begin(voice);
      expect(begin.kind, FallEnableBeginKind.prompt);
      expect(begin.gateBypassed, isTrue);
      final confirm = await session.confirm(voice);
      expect(confirm.kind, FallEnableConfirmKind.enabled);
      expect(confirm.gateBypassed, isTrue);
    });

    test('süre yeterliyse atlandı denmez', () async {
      final begin = await session.begin(voice);
      expect(begin.gateBypassed, isFalse);
    });
  });

  test('kaynak kodu: oturum dosyası acil durum akışını hiç anmaz', () {
    final code = File('lib/fall/fall_enable_session.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.toLowerCase().contains('sos'), isFalse);
  });
}

/// Sırayı günlüğe yazan sahte onay deposu.
class _OrderConsent implements FallConsentStore {
  final List<String> order;
  final MemoryFallConsentStore inner;

  _OrderConsent(this.order, this.inner);

  @override
  Future<bool> granted() => inner.granted();

  @override
  Future<bool> grant() {
    order.add('grant');
    return inner.grant();
  }

  @override
  Future<void> revoke() => inner.revoke();
}
