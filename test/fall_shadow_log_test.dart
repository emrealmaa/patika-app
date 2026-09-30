import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_detector.dart';
import 'package:patika_app/fall/fall_shadow_log.dart';

/// Faz 7c-1: gölge kaydı. Kalıcılık, 200 kayıt / 14 gün sınırı, bozuk dosya,
/// yalnızca darbe adımına ulaşanlar ve kayıtta konum/ham veri olmaması.
void main() {
  late DateTime clock;
  late MemoryFallLogStore store;
  late FallShadowLog log;

  setUp(() {
    clock = DateTime(2026, 9, 30, 12);
    store = MemoryFallLogStore();
    log = FallShadowLog(store, now: () => clock);
  });

  FallEvaluation eval(FallOutcome outcome, {int ff = 300}) => FallEvaluation(
        outcome: outcome,
        startMs: 0,
        freeFallMs: ff,
        peakG: 3.456,
        orientationDegrees: outcome == FallOutcome.noImpact ? null : 87.654,
        stillnessStdG: outcome == FallOutcome.noImpact ? null : 0.01234,
      );

  List<Object?> stored() => jsonDecode(store.content!) as List<Object?>;

  group('ne kaydedilir', () {
    test('darbe adımına ulaşan üç sonuç kaydedilir', () async {
      for (final o in [FallOutcome.noOrientationChange, FallOutcome.movement, FallOutcome.candidate]) {
        expect(await log.add(eval(o), source: 'phone_imu'), isTrue);
      }
      expect(log.records.map((r) => r.outcome),
          [FallOutcome.noOrientationChange, FallOutcome.movement, FallOutcome.candidate]);
      expect(stored(), hasLength(3));
    });

    test('darbesiz düşüş (noImpact) kaydedilmez, depoya hiç yazılmaz', () async {
      expect(await log.add(eval(FallOutcome.noImpact), source: 'phone_imu'), isFalse);
      expect(log.records, isEmpty);
      expect(store.writes, 0);
    });

    test('ALAN LİSTESİ KİLİTLİ: yalnızca zaman, kaynak, sonuç, özet değerler', () async {
      await log.add(eval(FallOutcome.candidate), source: 'phone_imu');
      final row = stored().single as Map<String, Object?>;
      // Yeni bir alan eklemek bilinçli bir karar olmalı: konum ve ham sensör
      // verisi bu kayda hiçbir zaman girmez (Faz 7c kararı 1).
      expect(row.keys.toSet(), {'at', 'src', 'out', 'ffMs', 'peakG', 'deg', 'std'});
      for (final v in row.values) {
        expect(v, anyOf(isNull, isA<num>(), isA<String>()), reason: 'iç içe veri (ham örnek dizisi) yok');
      }
    });

    test('değerler yuvarlanır, geri okunur', () async {
      await log.add(eval(FallOutcome.candidate), source: 'phone_imu');
      final row = stored().single as Map<String, Object?>;
      expect(row['peakG'], 3.46);
      expect(row['deg'], 87.7);
      expect(row['std'], 0.012);
      expect(row['at'], clock.millisecondsSinceEpoch);
      expect(row['src'], 'phone_imu');
      expect(row['out'], 'candidate');

      final again = FallShadowLog(store, now: () => clock);
      await again.load();
      final r = again.records.single;
      expect(r.at, clock);
      expect(r.outcome, FallOutcome.candidate);
      expect(r.freeFallMs, 300);
      expect(r.peakG, 3.46);
      expect(r.orientationDegrees, 87.7);
      expect(r.stillnessStdG, 0.012);
    });

    test('ölçülemeyen açı (null) da saklanır', () async {
      await log.add(
        const FallEvaluation(
            outcome: FallOutcome.noOrientationChange, startMs: 0, freeFallMs: 200, peakG: 3, stillnessStdG: 0.2),
        source: 'phone_imu',
      );
      final again = FallShadowLog(store, now: () => clock);
      await again.load();
      expect(again.records.single.orientationDegrees, isNull);
    });
  });

  group('sınırlar', () {
    test('en fazla 200 kayıt, en eskiler atılır', () async {
      for (var i = 0; i < 205; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await log.add(eval(FallOutcome.movement, ff: i), source: 'phone_imu');
      }
      expect(log.records, hasLength(FallShadowLog.maxRecords));
      expect(log.records.first.freeFallMs, 5);
      expect(log.records.last.freeFallMs, 204);
      expect(stored(), hasLength(200));
    });

    test('14 günden eski kayıt eklemede atılır', () async {
      await log.add(eval(FallOutcome.movement, ff: 1), source: 'phone_imu');
      clock = clock.add(const Duration(days: 14, minutes: 1));
      await log.add(eval(FallOutcome.movement, ff: 2), source: 'phone_imu');
      expect(log.records.map((r) => r.freeFallMs), [2]);
    });

    test('14 günden eski kayıt yüklemede atılır ve dosya güncellenir', () async {
      await log.add(eval(FallOutcome.movement, ff: 1), source: 'phone_imu');
      clock = clock.add(const Duration(days: 10));
      await log.add(eval(FallOutcome.movement, ff: 2), source: 'phone_imu');
      clock = clock.add(const Duration(days: 5));
      final writesBefore = store.writes;

      final again = FallShadowLog(store, now: () => clock);
      await again.load();
      expect(again.records.map((r) => r.freeFallMs), [2]);
      expect(store.writes, writesBefore + 1);
      expect(stored(), hasLength(1));
    });

    test('budanacak bir şey yoksa yükleme yazmaz', () async {
      await log.add(eval(FallOutcome.movement), source: 'phone_imu');
      final writesBefore = store.writes;
      await FallShadowLog(store, now: () => clock).load();
      expect(store.writes, writesBefore);
    });
  });

  group('dayanıklılık', () {
    test('bozuk JSON -> boş liste, çökme yok; sonraki ekleme dosyayı düzeltir', () async {
      store.content = '{bozuk';
      await log.load();
      expect(log.records, isEmpty);
      await log.add(eval(FallOutcome.candidate), source: 'phone_imu');
      expect(stored(), hasLength(1));
    });

    test('liste olmayan JSON -> boş liste', () async {
      store.content = '{"a": 1}';
      await log.load();
      expect(log.records, isEmpty);
    });

    test('tanınmayan satırlar atlanır, geçerliler kalır', () async {
      store.content = jsonEncode([
        {'at': 1, 'src': 'phone_imu', 'out': 'bilinmeyen', 'ffMs': 1, 'peakG': 3},
        {'at': 'dün', 'src': 'phone_imu', 'out': 'candidate', 'ffMs': 1, 'peakG': 3},
        42,
        {
          'at': clock.millisecondsSinceEpoch,
          'src': 'phone_imu',
          'out': 'movement',
          'ffMs': 250,
          'peakG': 2.9,
          'deg': null,
          'std': 0.3,
        },
      ]);
      await log.load();
      expect(log.records.single.freeFallMs, 250);
    });

    test('yazma hatası fırlatmaz, kayıt bellekte kalır', () async {
      store.failWrites = true;
      expect(await log.add(eval(FallOutcome.candidate), source: 'phone_imu'), isTrue);
      expect(log.records, hasLength(1));
      store.failWrites = false;
      await log.add(eval(FallOutcome.movement), source: 'phone_imu');
      expect(stored(), hasLength(2), reason: 'sonraki yazma ikisini de kaydeder');
    });

    test('beklenmeden art arda eklemeler birbirini ezmez', () async {
      await Future.wait([
        for (var i = 0; i < 5; i++) log.add(eval(FallOutcome.movement, ff: i), source: 'phone_imu'),
      ]);
      expect(stored(), hasLength(5));
      expect(log.records.map((r) => r.freeFallMs), [0, 1, 2, 3, 4]);
    });

    test('yüklemeden önce eklenirse var olan kayıtlar kaybolmaz', () async {
      await log.add(eval(FallOutcome.movement, ff: 1), source: 'phone_imu');
      final fresh = FallShadowLog(store, now: () => clock);
      await fresh.add(eval(FallOutcome.movement, ff: 2), source: 'phone_imu');
      expect(fresh.records.map((r) => r.freeFallMs), [1, 2]);
    });
  });

  group('silme', () {
    test('clear kaydı ve dosyayı siler, dinleyiciye haber verir', () async {
      await log.add(eval(FallOutcome.candidate), source: 'phone_imu');
      var notified = 0;
      log.addListener(() => notified++);
      await log.clear();
      expect(log.records, isEmpty);
      expect(store.content, isNull);
      expect(notified, 1);
    });
  });
}
