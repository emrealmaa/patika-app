import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_open_gate.dart';
import 'package:patika_app/fall/fall_open_state.dart';

/// Faz 7c-2, adım 1: açık moda geçişin kapıları, gölge sayacı ve kalıcı durum.
void main() {
  final t0 = DateTime(2026, 10, 1, 12);

  group('FallShadowTracker (kesintisiz süre)', () {
    late MemoryFallOpenState state;
    late DateTime now;
    late FallShadowTracker tracker;

    setUp(() {
      state = MemoryFallOpenState();
      now = t0;
      tracker = FallShadowTracker(state, now: () => now);
    });

    test('gölgeye geçince başlar, tekrar çağrılınca ilk an korunur', () async {
      await tracker.onModeChanged(FallMode.shadow);
      expect(state.since, t0);
      now = t0.add(const Duration(days: 3));
      await tracker.onModeChanged(FallMode.shadow);
      expect(state.since, t0, reason: 'açılış yoklaması süreyi sıfırlamaz');
    });

    test('kapalı olunca sıfırlanır; yeniden gölgeye geçince YENİDEN başlar', () async {
      await tracker.onModeChanged(FallMode.shadow);
      now = t0.add(const Duration(days: 6));
      await tracker.onModeChanged(FallMode.off);
      expect(state.since, isNull);
      now = t0.add(const Duration(days: 7));
      await tracker.onModeChanged(FallMode.shadow);
      expect(state.since, t0.add(const Duration(days: 7)));
    });

    test('shadow <-> on geçişi süreyi bozmaz', () async {
      await tracker.onModeChanged(FallMode.shadow);
      now = t0.add(const Duration(days: 8));
      await tracker.onModeChanged(FallMode.on);
      await tracker.onModeChanged(FallMode.shadow);
      expect(state.since, t0);
    });

    test('hiç başlamamış ve kapalıyken yazılacak bir şey yok', () async {
      await tracker.onModeChanged(FallMode.off);
      expect(state.since, isNull);
    });
  });

  group('FallOpenModeGate', () {
    bool direct = true;
    int contacts = 1;
    bool sms = true;
    DateTime? since;
    late DateTime now;

    FallOpenModeGate gate({ShadowGatePolicy policy = const ShadowGatePolicy()}) => FallOpenModeGate(
          directBuild: () async => direct,
          contactCount: () async => contacts,
          hasSmsPermission: () async => sms,
          shadowSince: () async => since,
          policy: policy,
          now: () => now,
        );

    setUp(() {
      direct = true;
      contacts = 1;
      sms = true;
      now = t0;
      since = t0.subtract(const Duration(days: 7));
    });

    test('hepsi tamamsa açılabilir', () async {
      final r = await gate().check();
      expect(r.open, isTrue);
      expect(r.block, isNull);
      expect(r.shadowGateBypassed, isFalse);
    });

    test('play derlemesi: engel, ve en başta (diğer kapılar bakılmadan)', () async {
      direct = false;
      contacts = 0;
      sms = false;
      since = null;
      expect((await gate().check()).block, FallOpenBlock.unsupportedBuild);
    });

    test('acil kişi yok', () async {
      contacts = 0;
      expect((await gate().check()).block, FallOpenBlock.noContacts);
    });

    test('SMS izni yok', () async {
      sms = false;
      expect((await gate().check()).block, FallOpenBlock.noSmsPermission);
    });

    test('kapı sırası: kişi yokluğu izin yokluğundan, o da gölge süresinden önce', () async {
      contacts = 0;
      sms = false;
      since = null;
      expect((await gate().check()).block, FallOpenBlock.noContacts);
      contacts = 1;
      expect((await gate().check()).block, FallOpenBlock.noSmsPermission);
      sms = true;
      expect((await gate().check()).block, FallOpenBlock.shadowTooShort);
    });

    test('gölge süresi tam 7 gün: geçer; 1 dakika eksik: geçmez', () async {
      since = t0.subtract(const Duration(days: 7));
      expect((await gate().check()).open, isTrue);
      since = t0.subtract(const Duration(days: 7)).add(const Duration(minutes: 1));
      final r = await gate().check();
      expect(r.block, FallOpenBlock.shadowTooShort);
      expect(r.daysLeft, 1);
    });

    test('kalan gün yukarı yuvarlanır ve 1..7 aralığında kalır', () async {
      since = t0.subtract(const Duration(days: 3, hours: 1));
      expect((await gate().check()).daysLeft, 4);
      since = t0;
      expect((await gate().check()).daysLeft, 7);
      since = null;
      final r = await gate().check();
      expect(r.block, FallOpenBlock.shadowTooShort);
      expect(r.daysLeft, 7, reason: 'bilinmeyen başlangıç = hiç başlamamış');
    });

    group('7 gün kapısının atlanması (yalnızca debug)', () {
      test('varsayılan politika atlamaz', () async {
        since = null;
        expect((await gate().check()).block, FallOpenBlock.shadowTooShort);
        expect(const ShadowGatePolicy().skips, isFalse);
      });

      test('debug + açıkça istenince atlar ve İZ BIRAKIR (bypassed bayrağı + log)', () async {
        since = null;
        final logs = <String?>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => logs.add(message);
        addTearDown(() => debugPrint = original);

        final r = await gate(policy: const ShadowGatePolicy(debugSkip: true)).check();
        expect(r.open, isTrue);
        expect(r.shadowGateBypassed, isTrue);
        expect(logs.join('\n'), contains('gün kapısı atlandı'));
      });

      test('süre zaten yeterliyse atlanmış sayılmaz (iz yok)', () async {
        final r = await gate(policy: const ShadowGatePolicy(debugSkip: true)).check();
        expect(r.open, isTrue);
        expect(r.shadowGateBypassed, isFalse);
      });

      test('atlama diğer kapıları AŞMAZ (kişi yok, izin yok, play)', () async {
        since = null;
        const policy = ShadowGatePolicy(debugSkip: true);
        contacts = 0;
        expect((await gate(policy: policy).check()).block, FallOpenBlock.noContacts);
        contacts = 1;
        sms = false;
        expect((await gate(policy: policy).check()).block, FallOpenBlock.noSmsPermission);
        sms = true;
        direct = false;
        expect((await gate(policy: policy).check()).block, FallOpenBlock.unsupportedBuild);
      });

      test('test derlemesi release değil: bayrak burada açılabilir; release\'te kapalı olduğu kaynaktan kilitli', () {
        expect(kReleaseMode, isFalse);
        final code = File('lib/fall/fall_open_gate.dart')
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        // Release'te atlama imkânsız: tek giriş noktası !kReleaseMode ile korunur.
        expect(code, contains('_skip = !kReleaseMode && debugSkip'));
      });
    });
  });

  group('FallOpenState (bellek uygulaması)', () {
    test('tam metin bayrağı varsayılan false, işaretlenince true', () async {
      final s = MemoryFallOpenState();
      expect(await s.fullTextHeard(), isFalse);
      await s.markFullTextHeard();
      expect(await s.fullTextHeard(), isTrue);
    });
  });

  group('kaynak kodu kilitleri', () {
    test('kalıcı anahtarlar ayar dosyasından ayrı (ayarları sıfırla silmesin)', () {
      final code = File('lib/fall/fall_open_state.dart').readAsStringSync();
      expect(code, contains("'patika.fallOpenFullTextHeard.v1'"));
      expect(code, contains("'patika.fallShadowSince.v1'"));
      final settings = File('lib/settings/settings.dart').readAsStringSync();
      expect(settings.contains('fallShadowSince'), isFalse);
      expect(settings.contains('FullTextHeard'), isFalse);
    });
  });
}
