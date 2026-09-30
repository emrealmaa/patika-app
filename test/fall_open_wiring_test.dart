import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_act.dart';
import 'package:patika_app/fall/fall_consent_store.dart';
import 'package:patika_app/fall/fall_enable_session.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_open_state.dart';
import 'package:patika_app/fall/synthetic_signals.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/sos/sos_config.dart';
import 'package:patika_app/sos/sos_controller.dart';

import 'emergency_contact_test.dart' show command, answer;
import 'fakes.dart';
import 'sos_wiring_test.dart' show ayse, ali;
import 'test_harness.dart';

/// Faz 7c-2, adım 5: açık mod uygulamada uçtan uca. Gerçek AppState, gerçek
/// monitör, gerçek köprü ve gerçek SosController; yalnızca platform sahte.
/// Hiçbir yerde gerçek SMS/arama/112 yok (`FakeDirectActions`).
void main() {
  late FakeDirectActions actions;
  late DateTime now;
  var clockMs = 0;

  Harness open({
    Settings initial = const Settings(fallMode: FallMode.shadow),
    MemoryFallOpenState? openState,
    List<dynamic> contacts = const [ayse, ali],
    bool consent = false,
    bool sms = true,
  }) {
    actions = FakeDirectActions();
    now = DateTime(2026, 10, 10, 12);
    return Harness(
      direct: actions,
      emergencyContacts: [for (final c in contacts) c],
      initial: initial,
      fallOpenState: openState,
      fallConsent: MemoryFallConsentStore(value: consent),
      smsPermission: sms,
      fallNow: () => now,
    );
  }

  void run(FakeAsync async, Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  void realFall(Harness h, FakeAsync async) {
    h.fallMotion.push(syntheticScenario(SyntheticScenario.realisticFall, startMs: clockMs));
    clockMs += 100000;
    async.flushMicrotasks();
  }

  /// "düşme algılamayı aç" -> uyarı -> "anladım, aç".
  void enableByVoice(Harness h, FakeAsync async) {
    command(h, async, 'düşme algılamayı aç');
    h.speakAll(async);
    answer(h, async, 'anladım, aç');
    h.speakAll(async);
    async.flushMicrotasks();
  }

  /// Acil kişi deposunun o anki içeriği.
  List<dynamic> readContacts(Harness h, FakeAsync async) {
    List<dynamic>? result;
    h.emergencyContacts.readAll().then((v) => result = v);
    async.flushMicrotasks();
    return result ?? const [];
  }

  setUp(() => clockMs = 0);

  group('açma -> tetikleme (uçtan uca)', () {
    test('sesle iki adımda açılır; gerçek düşme 25 sn geri sayım başlatır; iptal edilmezse gönderilir', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        expect(h.app.fall.mode, FallMode.on);
        expect(h.settings.value.fallMode, FallMode.on);
        expect(h.tts.spoken.join(' '), contains(Tr.fallOpenWarningFull));
        expect(h.tts.spoken.join(' '), contains(Tr.fallOpenEnabled));
        expect(h.openStateHeard, isTrue);

        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.app.sos.status.value.source, SosSource.fall);
        expect(actions.sms, isEmpty);

        run(async, const Duration(seconds: 24));
        expect(actions.sms, isEmpty, reason: '25 sn dolmadan gitmez');
        run(async, const Duration(seconds: 40));
        expect(actions.sms.map((s) => s.$1), [ayse.number, ali.number]);
        expect(actions.calls, isNot(contains('112')), reason: 'düşmede 112 kendiliğinden aranmaz');
        h.dispose();
      });
    });

    test('ekran ve ses AYNI oturumu paylaşır: sesle başlayan açma ekrandan onaylanamaz', () {
      fakeAsync((async) {
        final h = open();
        command(h, async, 'düşme algılamayı aç');
        h.speakAll(async);
        expect(h.app.fallEnable.pendingChannel, FallEnableChannel.voice);

        FallEnableConfirm? screen;
        h.app.fallEnable.confirm(FallEnableChannel.screen).then((c) => screen = c);
        async.flushMicrotasks();
        expect(screen!.kind, FallEnableConfirmKind.wrongChannel);
        expect(h.app.fall.mode, FallMode.shadow);

        // Ayarlar ekranının kontrolcüsü de aynı oturumu kullanıyor.
        expect(identical(h.app.fallSettings.session, h.app.fallEnable), isTrue);
        h.dispose();
      });
    });

    test('"evet" açmaz; sesli açma iptal edilince mod gölge kalır ve düşme SOS başlatmaz', () {
      fakeAsync((async) {
        final h = open();
        command(h, async, 'düşme algılamayı aç');
        h.speakAll(async);
        answer(h, async, 'evet');
        h.speakAll(async);
        expect(h.app.fall.mode, FallMode.shadow);
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('gölge modunda (açık değil) gerçek düşme SOS BAŞLATMAZ', () {
      fakeAsync((async) {
        final h = open();
        async.flushMicrotasks();
        realFall(h, async);
        run(async, const Duration(minutes: 2));
        expect(h.app.sos.phase, SosPhase.idle);
        expect(actions.sms, isEmpty);
        expect(h.app.fallLog.records, hasLength(1), reason: 'gölge kaydı yine tutulur');
        h.dispose();
      });
    });
  });

  group('silah ve guard: ayar dosyasındaki "on" tek başına yetmez (karar 4)', () {
    String spoken(Harness h) => h.tts.spoken.join(' | ');

    test('kayıtlı "on" + bu cihazda onay + kapılar tamam: açılışta silahlanır, düşme SOS başlatır', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on), consent: true);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.on, reason: 'düşmedi');
        expect(h.tts.spoken, isEmpty, reason: 'sorun yok: hiçbir şey söylenmez');
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.countdown);
        h.dispose();
      });
    });

    test('kayıtlı "on" ama BU CİHAZDA onay yok (yedekten/başka cihazdan geldi): gölgeye düşer, SÖYLER, tetiklemez', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenNeedsReconfirm));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        expect(actions.sms, isEmpty);
        h.dispose();
      });
    });

    test('onay yokken düşmeden sonra yeniden açmak İKİ ADIM ister ve sonra çalışır', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on));
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.shadow);

        enableByVoice(h, async);
        expect(h.settings.value.fallMode, FallMode.on);
        expect(h.fallConsent.value, isTrue, reason: 'bu cihazda onay kaydedildi');
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.countdown);
        h.dispose();
      });
    });

    test('kayıtlı "on" ama gölge süresi yok: gölgeye düşer, nedeni SÖYLER', () {
      fakeAsync((async) {
        final h = open(
          initial: const Settings(fallMode: FallMode.on),
          openState: MemoryFallOpenState(),
          consent: true,
        );
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenDropped(Tr.fallOpenBlockedShadow(7))));
        realFall(h, async);
        run(async, const Duration(minutes: 2));
        expect(h.app.sos.phase, SosPhase.idle);
        expect(actions.sms, isEmpty);
        h.dispose();
      });
    });

    test('kayıtlı "on" ama acil kişi yok: gölgeye düşer, nedeni SÖYLER', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on), contacts: const [], consent: true);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenDropped(Tr.fallOpenBlockedNoContacts)));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('kayıtlı "on" ama SMS izni geri alınmış: gölgeye düşer, nedeni SÖYLER', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on), consent: true, sms: false);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenDropped(Tr.fallOpenBlockedNoSms)));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('gölgeye düşünce onay da silinir (yeniden açmak yeniden onay ister)', () {
      fakeAsync((async) {
        final h = open(initial: const Settings(fallMode: FallMode.on), contacts: const [], consent: true);
        async.flushMicrotasks();
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(h.fallConsent.value, isFalse);
        h.dispose();
      });
    });

    test('son acil kişi silinince açık mod gölgeye düşer ve SÖYLER; bir kişi kalırsa açık kalır', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        expect(h.settings.value.fallMode, FallMode.on);

        command(h, async, 'acil kişi sil Ayşe');
        h.speakAll(async);
        answer(h, async, 'evet');
        h.speakAll(async);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(readContacts(h, async), hasLength(1));
        expect(h.settings.value.fallMode, FallMode.on, reason: 'bir kişi kaldı: açık kalır');

        command(h, async, 'acil kişi sil Ali');
        h.speakAll(async);
        answer(h, async, 'evet');
        h.speakAll(async);
        async.flushMicrotasks();
        h.speakAll(async);
        expect(readContacts(h, async), isEmpty);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenDropped(Tr.fallOpenBlockedNoContacts)));
        expect(h.fallConsent.value, isFalse);
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('onay kaydı yazılamazsa açık mod AÇILMAZ ve söylenir', () {
      fakeAsync((async) {
        final h = open();
        h.fallConsent.failGrant = true;
        enableByVoice(h, async);
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenStorageFailed));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('mod gölgeye/kapalıya düşünce silah düşer, onay silinir; düşme SOS başlatmaz', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        expect(h.app.fall.mode, FallMode.on);
        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        expect(h.fallConsent.value, isFalse, reason: 'açık moddan çıkınca onay silinir');
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle, reason: 'gölgeye düştü');
        h.dispose();
      });
    });

    test('ayarları doğrudan yeniden "on" yapmak (onaysız) silahlamaz: bu cihazda onay yok', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        h.speakAll(async);
        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.on)); // iki adımı atlayan yol
        async.flushMicrotasks();
        h.speakAll(async);
        async.flushMicrotasks();
        expect(h.settings.value.fallMode, FallMode.shadow);
        expect(spoken(h), contains(Tr.fallOpenNeedsReconfirm));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });
  });

  group('kapatma (karar: "kapat" = tam off; gölge sayacı sıfırlanır)', () {
    test('sesli "düşme algılamayı kapat": tek adım, off, silah düşer, düşme SOS başlatmaz', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        command(h, async, 'düşme algılamayı kapat');
        h.speakAll(async);
        async.flushMicrotasks();
        expect(h.settings.value.fallMode, FallMode.off);
        expect(h.app.fall.mode, FallMode.off);
        expect(h.fallOpenState.since, isNull, reason: 'gölge sayacı sıfırlandı');
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('kapatıp yeniden açmak YENİDEN iki adım ister ve gölge süresi yeniden dolmalı', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        command(h, async, 'düşme algılamayı kapat');
        h.speakAll(async);
        async.flushMicrotasks();
        h.settings.update(h.settings.value.copyWith(fallMode: FallMode.shadow));
        async.flushMicrotasks();
        expect(h.fallOpenState.since, isNotNull);

        command(h, async, 'düşme algılamayı aç');
        h.speakAll(async);
        expect(h.tts.spoken.last, contains(Tr.fallOpenBlockedShadow(7)),
            reason: 'sayaç sıfırlandı: bugün başladı, 7 gün kaldı');
        expect(h.app.fall.mode, FallMode.shadow);
        h.dispose();
      });
    });
  });

  group('bastırma ve etiketler (uygulamada)', () {
    test('düşme SOS\'u iptal edilince 2 dk bastırma; sonrasında yine tetikler; elle SOS etkilenmez', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        realFall(h, async);
        run(async, const Duration(seconds: 5));
        expect(h.app.sos.cancel(SosCancelSource.voice), isTrue);
        run(async, const Duration(seconds: 1));

        now = now.add(const Duration(minutes: 1));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.idle, reason: '2 dk dolmadı');

        // Elle SOS bastırmadan etkilenmez.
        h.app.triggerSos();
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.app.sos.status.value.source, SosSource.voice);
        h.app.sos.cancel(SosCancelSource.voice);

        now = now.add(const Duration(minutes: 1, seconds: 1));
        realFall(h, async);
        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.app.sos.status.value.source, SosSource.fall);
        h.dispose();
      });
    });
  });

  group('süren akışlar (karar 8)', () {
    test('SIRADAN diyalog (acil kişi ekle) düşmede kesilir; geri sayım başlar; mikrofon oturumu kapanır', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        command(h, async, 'acil kişi ekle');
        h.speakAll(async);
        expect(h.app.dialogs.active, isTrue);

        realFall(h, async);
        expect(h.app.dialogs.active, isFalse);
        expect(h.app.sos.phase, SosPhase.countdown);
        expect(h.app.sos.status.value.source, SosSource.fall);
        h.dispose();
      });
    });

    test('elle SOS sürerken gelen düşme adayı onu KESMEZ, ikinci SOS başlatmaz', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        h.app.triggerSos();
        async.flushMicrotasks();
        run(async, const Duration(seconds: 2));
        realFall(h, async);
        expect(h.app.sos.status.value.source, SosSource.voice);
        expect(h.app.sos.phase, SosPhase.countdown);
        run(async, const Duration(seconds: 10));
        expect(actions.sms.map((s) => s.$1).toSet(), {ayse.number, ali.number});
        expect(actions.sms, hasLength(2), reason: 'tek SOS, tek SMS turu');
        h.dispose();
      });
    });
  });

  group('kayıt etiketi act (karar 10, uygulamada)', () {
    List<FallAct> acts(Harness h) => [for (final r in h.app.fallLog.records) r.act];

    test('gölge: etiket none, dosyada act anahtarı yok', () {
      fakeAsync((async) {
        final h = open();
        async.flushMicrotasks();
        realFall(h, async);
        expect(acts(h), [FallAct.none]);
        expect(h.fallLogStore.content, isNot(contains('"act"')));
        h.dispose();
      });
    });

    test('açık mod: geri sayım başlayınca started, iptalde cancelled (dosyaya da yazılır)', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        realFall(h, async);
        async.flushMicrotasks();
        expect(acts(h), [FallAct.started]);
        h.app.sos.cancel(SosCancelSource.voice);
        async.flushMicrotasks();
        expect(acts(h), [FallAct.cancelled]);
        expect(h.fallLogStore.content, contains('"act":"cancelled"'));
        h.dispose();
      });
    });

    test('iptal edilmezse gönderim sonunda sent', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        realFall(h, async);
        for (var i = 0; i < 60; i++) {
          run(async, const Duration(seconds: 1));
          h.speakAll(async); // gönderim sonucu konuşma bitince ilerler
        }
        expect(acts(h), [FallAct.sent]);
        h.dispose();
      });
    });

    test('bastırılan ikinci aday suppressed; ilk kayıt cancelled kalır', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        realFall(h, async);
        run(async, const Duration(seconds: 2));
        h.app.sos.cancel(SosCancelSource.voice);
        run(async, const Duration(seconds: 1));
        now = now.add(const Duration(seconds: 30));
        realFall(h, async);
        async.flushMicrotasks();
        expect(acts(h), [FallAct.cancelled, FallAct.suppressed]);
        h.dispose();
      });
    });

    test('süren SOS yüzünden başlatılmayan aday suppressed', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        h.app.triggerSos();
        async.flushMicrotasks();
        realFall(h, async);
        async.flushMicrotasks();
        expect(acts(h), [FallAct.suppressed]);
        h.dispose();
      });
    });

    test('sentetik düğme açık modda bile none (hiçbir eylem yok)', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        h.app.runFallScenario(SyntheticScenario.realisticFall);
        async.flushMicrotasks();
        expect(acts(h), [FallAct.none]);
        h.dispose();
      });
    });

    test('Test Modu satırı etiketi yazıyla söyler; none için hiçbir şey eklemez', () {
      String line(String? act) => Tr.fallRecordLine(
          time: '10.10 12:00', source: 'phone_imu', outcome: 'düşme adayı', freeFallMs: 300, peakG: 3.4, act: act);
      expect(line(null), isNot(contains('Acil durum')));
      expect(line(Tr.fallActCancelled), endsWith('. Acil durum: iptal edildi'));
      expect(Tr.fallActSent, 'gönderildi');
    });
  });

  group('tekrar duyuru (karar 6)', () {
    /// Geri sayımı bir saniye ilerletir; [speak] doluysa konuşmaları bitirir.
    void second(Harness h, FakeAsync async, {bool speak = true}) {
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      if (speak) h.speakAll(async);
    }

    /// Düşme geri sayımı başlar, giriş cümlesi bitince mikrofon "iptal" için açılır.
    Harness fallCountdown(FakeAsync async) {
      final h = open();
      enableByVoice(h, async);
      realFall(h, async);
      expect(h.app.sos.phase, SosPhase.countdown);
      h.speakAll(async);
      async.elapse(const Duration(milliseconds: 600));
      async.flushMicrotasks();
      return h;
    }

    test('kalan 15 ve 5 saniyede kısa cümle; başka saniyede yok', () {
      fakeAsync((async) {
        final h = fallCountdown(async);
        final spoken = <int, bool>{};
        for (var elapsed = 1; elapsed <= 24; elapsed++) {
          final before = h.tts.spoken.length;
          second(h, async);
          final remaining = 25 - elapsed;
          final reminder = h.tts.spoken.skip(before).any((t) => t.contains('saniye kaldı'));
          spoken[remaining] = reminder;
        }
        expect([for (final e in spoken.entries) if (e.value) e.key], [15, 5]);
        expect(h.tts.spoken, contains(Tr.sosFallCountdownReminder(15)));
        expect(h.tts.spoken, contains(Tr.sosFallCountdownReminder(5)));
        expect(Tr.sosFallCountdownReminder(15), '15 saniye kaldı, iptal için iptal deyin');
        h.dispose();
      });
    });

    test('duyuru konuşulurken mikrofon KAPALI (kendi sesimiz iptal sayılmaz), bitince yeniden açılır', () {
      fakeAsync((async) {
        final h = fallCountdown(async);
        expect(h.speech.listening, isTrue, reason: 'giriş cümlesinden sonra dinliyor');
        for (var i = 0; i < 9; i++) {
          second(h, async);
        }
        expect(h.speech.listening, isTrue, reason: 'duyuru öncesi dinlemeye devam');

        second(h, async, speak: false); // kalan 15: duyuru başladı, henüz bitmedi
        expect(h.tts.spoken.last, Tr.sosFallCountdownReminder(15));
        expect(h.speech.listening, isFalse, reason: 'konuşurken mikrofon kapalı');
        expect(h.app.sos.phase, SosPhase.countdown);

        // Konuşurken "iptal" sesi gelse bile dinleyen yok: SOS sürer.
        h.speech.say('iptal');
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.countdown, reason: 'kapalı mikrofon iptal üretemez');

        h.speakAll(async); // duyuru bitti
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(h.speech.listening, isTrue, reason: 'bitince sesli iptal yeniden açık');
        h.speech.say('iptal');
        async.flushMicrotasks();
        expect(h.app.sos.phase, SosPhase.idle, reason: 'duyurudan sonra sesli iptal çalışır');
        h.dispose();
      });
    });

    test('duyuru sırasında ekran iptali çalışır', () {
      fakeAsync((async) {
        final h = fallCountdown(async);
        for (var i = 0; i < 10; i++) {
          second(h, async, speak: false);
          h.tts.finishCurrent();
          async.flushMicrotasks();
        }
        expect(h.app.sos.inCountdown, isTrue);
        expect(h.app.sos.cancel(SosCancelSource.screen), isTrue);
        expect(h.app.sos.phase, SosPhase.idle);
        h.dispose();
      });
    });

    test('elle SOS için (sesli/gözlük) tekrar duyuru YOK', () {
      fakeAsync((async) {
        final h = open();
        async.flushMicrotasks();
        h.app.triggerSos();
        async.flushMicrotasks();
        for (var i = 0; i < 6; i++) {
          second(h, async);
        }
        expect(h.tts.spoken.where((t) => t.contains('saniye kaldı')), isEmpty);
        h.dispose();
      });
    });

    test('yapılandırma: yalnızca kalan 15 ve 5; 25 sn içinde', () {
      expect(SosConfig.fallReminderSeconds, [15, 5]);
      expect(SosConfig.fallReminderSeconds.every((s) => s < SosConfig.fallCountdown.inSeconds), isTrue);
    });
  });

  group('sentetik kaynak (karar 11)', () {
    test('Test Modu düğmesi açık modda bile SOS başlatmaz, hiçbir mesaj/arama gitmez', () {
      fakeAsync((async) {
        final h = open();
        enableByVoice(h, async);
        h.app.runFallScenario(SyntheticScenario.realisticFall);
        async.flushMicrotasks();
        run(async, const Duration(minutes: 2));
        expect(h.app.fallLog.records.map((r) => r.source), contains('synthetic'));
        expect(h.app.sos.phase, SosPhase.idle);
        expect(h.app.sos.history, isEmpty);
        expect(actions.sms, isEmpty);
        expect(actions.calls, isEmpty);
        h.dispose();
      });
    });
  });
}
