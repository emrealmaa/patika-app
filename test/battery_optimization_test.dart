import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/platform/battery_optimization.dart';

import 'fakes.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

class FakeBatteryOptimization implements BatteryOptimization {
  bool ignoring;
  BatteryExemptionUi ui;

  /// Pencere/ayar açıldıktan sonra kullanıcının muafiyeti vermesi (sn sonra).
  int? grantAfterChecks;
  int requests = 0;
  int _checksAfterRequest = 0;

  FakeBatteryOptimization({
    this.ignoring = false,
    this.ui = BatteryExemptionUi.dialog,
    this.grantAfterChecks,
  });

  @override
  Future<bool> isIgnoring() async {
    if (requests > 0) {
      _checksAfterRequest++;
      final after = grantAfterChecks;
      if (after != null && _checksAfterRequest > after) ignoring = true;
    }
    return ignoring;
  }

  @override
  Future<BatteryExemptionUi> request() async {
    requests++;
    return ui;
  }
}

/// Madde 3b: pil optimizasyonu muafiyeti. `direct`te pencere, `play`de ayar
/// ekranı; ikisi de önce sesle açıklanır, sonuç yoklanır ve söylenir.
void main() {
  test('zaten muafsa hiçbir şey söylenmez, açılmaz', () {
    fakeAsync((async) {
      final opt = FakeBatteryOptimization(ignoring: true);
      final h = Harness(batteryOptimization: opt);
      h.app.requestBatteryExemption();
      h.speakAll(async);
      expect(h.tts.spoken, isEmpty);
      expect(opt.requests, 0);
      h.dispose();
    });
  });

  test('direct: pencere açıklaması, sonra pencere; verilince "kaldırıldı"', () {
    fakeAsync((async) {
      final opt = FakeBatteryOptimization(grantAfterChecks: 3);
      final h = Harness(batteryOptimization: opt, direct: FakeDirectActions());
      h.app.requestBatteryExemption();
      async.flushMicrotasks();
      expect(h.tts.spoken, [Tr.batteryOptWhyDirect]);
      expect(opt.requests, 0, reason: 'pencere açıklama bitmeden açılmaz');
      h.speakAll(async);
      expect(opt.requests, 1);
      for (var i = 0; i < 5; i++) {
        async.elapse(const Duration(seconds: 1));
        h.speakAll(async);
      }
      expect(h.tts.spoken.last, Tr.batteryOptGranted);
      h.dispose();
    });
  });

  test('play: ayar ekranı yönlendirmesi; verilmezse 60 sn sonra "kaldırılmadı"', () {
    fakeAsync((async) {
      final opt = FakeBatteryOptimization(ui: BatteryExemptionUi.settings);
      final h = Harness(batteryOptimization: opt);
      h.app.requestBatteryExemption();
      h.speakAll(async);
      expect(h.tts.spoken.first, Tr.batteryOptWhyPlay);
      async.elapse(const Duration(seconds: 59));
      h.speakAll(async);
      expect(h.tts.spoken, [Tr.batteryOptWhyPlay]);
      async.elapse(const Duration(seconds: 2));
      h.speakAll(async);
      expect(h.tts.spoken.last, Tr.batteryOptNotGranted);
      h.dispose();
    });
  });

  test('ayar açılamazsa söylenir', () {
    fakeAsync((async) {
      final opt = FakeBatteryOptimization(ui: BatteryExemptionUi.failed);
      final h = Harness(batteryOptimization: opt);
      h.app.requestBatteryExemption();
      h.speakAll(async);
      expect(h.tts.spoken.last, Tr.batteryOptFailed);
      h.dispose();
    });
  });

  test('izin yalnızca direct manifestinde', () {
    const perm = 'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS';
    expect(File('android/app/src/direct/AndroidManifest.xml').readAsStringSync(), contains(perm));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), isNot(contains(perm)));
  });

  test('metinler yasaklı kelime içermez', () {
    final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
    final start = source.indexOf('// --- Pil optimizasyonu muafiyeti');
    final next = source.indexOf('\n  // --- ', start + 10);
    final code = source
        .substring(start, next)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final literals = RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(code).map((m) => m.group(1)!).toList();
    expect(literals.length, greaterThan(5));
    for (final t in literals) {
      expect(bannedIn(t), isEmpty, reason: t);
    }
  });
}
