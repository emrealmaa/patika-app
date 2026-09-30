import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/command_router.dart';
import 'package:patika_app/commands/handlers/fall_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/fall/fall_consent_store.dart';
import 'package:patika_app/fall/fall_enable_session.dart';
import 'package:patika_app/fall/fall_mode.dart';
import 'package:patika_app/fall/fall_open_gate.dart';
import 'package:patika_app/fall/fall_open_state.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/voice/dialog_manager.dart';
import 'package:patika_app/voice/dialogs/fall_enable_flow.dart';

import 'emergency_contact_test.dart' show answer;
import 'test_harness.dart';

/// Faz 7c-2, adım 3: sesli yüzey. Açma her zaman iki adımlı ve yalnızca dar
/// "anladım aç" kalıplarıyla; "evet", tek başına "aç" ya da cümle ortasındaki
/// geçiş AÇMAZ.
void main() {
  group('"anladım, aç" kalıpları (karar 2)', () {
    test('kabul edilenler', () {
      for (final text in [
        'anladım aç',
        'Anladım, aç',
        'ANLADIM AÇ',
        'kabul ediyorum aç',
        'Kabul ediyorum, aç.',
        'onaylıyorum aç',
        'lütfen anladım aç',
        'tamam anladım aç',
        'anladım aç lütfen',
      ]) {
        expect(classifyFallEnableConfirm(text), isTrue, reason: '"$text"');
      }
    });

    test('reddedilenler: tek başına aç, evet, tamam, anladım, cümle içinde', () {
      for (final text in [
        'aç',
        'evet',
        'tamam',
        'anladım',
        'evet aç',
        'tamam aç',
        'anladım açma',
        'anladım açabilirsin',
        'anladım açılsın',
        'hayır anladım aç',
        'anladım aç ve gönder',
        'bunu anladım aç dedi',
        'kabul ediyorum',
        'onaylıyorum',
        '',
      ]) {
        expect(classifyFallEnableConfirm(text), isFalse, reason: '"$text"');
      }
    });

    test('normal komut olarak hiçbir niyete dönüşmez', () {
      expect(classifyVoiceCommand('anladım aç').intent, isNot(PatikaIntent.dusme));
    });
  });

  group('sınıflandırıcı: DÜŞME', () {
    void expectFall(String text, String entity) {
      final cmd = classifyVoiceCommand(text);
      expect(cmd.intent, PatikaIntent.dusme, reason: '"$text" niyeti');
      expect(cmd.entity, entity, reason: '"$text" entity');
    }

    test('aç / kapat', () {
      expectFall('düşme algılamayı aç', 'ac');
      expectFall('Düşme algılamayı aç.', 'ac');
      expectFall('düşme algılamayı açar mısın', 'ac');
      expectFall('lütfen düşme algılamayı aç', 'ac');
      expectFall('düşme algılama özelliğini aç', 'ac');
      expectFall('düşme algılamayı kapat', 'kapat');
      expectFall('düşme algılamayı durdur', 'kapat');
      expectFall('düşme algılamayı kapatır mısın', 'kapat');
    });

    test('gölge modu', () {
      expectFall('gölge modunu aç', 'golge_ac');
      expectFall('gölge modunu kapat', 'golge_kapat');
      expectFall('gölge modu kapat', 'golge_kapat');
    });

    test('durum', () {
      expectFall('düşme algılama durumu', 'durum');
      expectFall('düşme algılama durumu ne', 'durum');
      expectFall('düşme algılama açık mı', 'durum');
      expectFall('düşme algılama kapalı mı', 'durum');
    });

    test('yalnızca TÜM cümle: cümle içinde geçenler eşleşmez', () {
      for (final text in [
        "Ahmet'e düşme algılamayı aç de",
        'düşme algılamayı açmayı unutma',
        'düşme algılamayı aç ve Ahmet i ara',
        'dün düşme algılamayı kapattım',
        'düşme algılama',
        'düşme',
        'gölge',
      ]) {
        expect(classifyVoiceCommand(text).intent, isNot(PatikaIntent.dusme), reason: '"$text"');
      }
    });

    test('komşu niyetler bozulmadı (7b dersi): acil durum SOS, durum DURUM, dur DUR, hava durumu HAVA', () {
      expect(classifyVoiceCommand('acil durum').intent, PatikaIntent.sos);
      expect(classifyVoiceCommand('yardım').intent, PatikaIntent.sos);
      expect(classifyVoiceCommand('durum').intent, PatikaIntent.durum);
      expect(classifyVoiceCommand('pil ne kadar').intent, PatikaIntent.durum);
      expect(classifyVoiceCommand('dur').intent, PatikaIntent.dur);
      expect(classifyVoiceCommand('hava durumu').intent, PatikaIntent.hava);
      expect(classifyVoiceCommand('bildirimleri kapat').intent, PatikaIntent.ayar);
      expect(classifyVoiceCommand('navigasyonu kapat').intent, PatikaIntent.navigasyonBitir);
      expect(classifyVoiceCommand('acil kişi ekle').intent, PatikaIntent.acilKisi);
    });

    test('SOS her zaman önce: düşme cümlesine "yardım" karışırsa SOS', () {
      expect(classifyVoiceCommand('yardım düşme algılamayı aç').intent, PatikaIntent.sos);
    });

    test('wire adları', () {
      expect(PatikaIntent.fromWireName('DUSME'), PatikaIntent.dusme);
      expect(PatikaIntent.fromWireName('DÜŞME'), PatikaIntent.dusme);
    });
  });

  group('FallEnableFlow (sesli diyalog)', () {
    late MemoryFallOpenState state;
    late FallMode mode;
    late List<FallMode> setCalls;
    late int contacts;
    late bool sms;
    late bool direct;
    late DateTime? since;
    late DateTime now;

    FallEnableSession session({ShadowGatePolicy policy = const ShadowGatePolicy()}) => FallEnableSession(
          gate: FallOpenModeGate(
            directBuild: () async => direct,
            contactCount: () async => contacts,
            hasSmsPermission: () async => sms,
            shadowSince: () async => since,
            policy: policy,
            now: () => now,
          ),
          state: state,
          consent: MemoryFallConsentStore(),
          currentMode: () => mode,
          setMode: (m) async {
            setCalls.add(m);
            mode = m;
          },
        );

    setUp(() {
      state = MemoryFallOpenState();
      mode = FallMode.shadow;
      setCalls = [];
      contacts = 1;
      sms = true;
      direct = true;
      now = DateTime(2026, 10, 10, 12);
      since = now.subtract(const Duration(days: 8));
    });

    test('ilk sefer: TAM uyarı + "anladım, aç deyin"; "Patika acil durum servisi değildir" içerir', () async {
      final step = await FallEnableFlow(session()).begin() as AskStep;
      expect(step.prompt, contains(Tr.fallOpenWarningFull));
      expect(step.prompt, contains(Tr.fallOpenConfirmInstruction));
      expect(Tr.fallOpenWarningFull, contains('Patika acil durum servisi değildir'));
      expect(Tr.fallOpenWarningFull, contains('deneysel'));
      expect(mode, FallMode.shadow, reason: 'uyarı okunurken mod açılmaz');
      expect(setCalls, isEmpty);
    });

    test('"anladım aç" açar; bayrak yazılır; sonraki açışta kısa hatırlatma', () async {
      final s = session();
      final flow = FallEnableFlow(s);
      await flow.begin();
      final done = await flow.onReply('anladım, aç') as FinishStep;
      expect(done.result.success, isTrue);
      expect(done.result.message, Tr.fallOpenEnabled);
      expect(mode, FallMode.on);
      expect(state.heard, isTrue);

      await s.closeOpenMode();
      final again = await FallEnableFlow(s).begin() as AskStep;
      expect(again.prompt, contains(Tr.fallOpenWarningShort));
      expect(again.prompt, isNot(contains(Tr.fallOpenWarningFull)));
      // Kısa hatırlatmada da iki adım: uyarıdan sonra mod hâlâ gölge.
      expect(mode, FallMode.shadow);
    });

    test('"evet", "tamam", tek başına "aç" AÇMAZ: bir kez ipucu, ikincisinde iptal', () async {
      final s = session();
      final flow = FallEnableFlow(s);
      await flow.begin();
      for (final wrong in ['evet', 'tamam', 'aç']) {
        // Her deneme yeni akışla: ilki ipucu verir.
        final f = FallEnableFlow(s);
        await f.begin();
        final hint = await f.onReply(wrong);
        expect(hint, isA<AskStep>(), reason: '"$wrong" ipucu');
        expect((hint as AskStep).prompt, Tr.fallOpenConfirmHint);
        expect(mode, FallMode.shadow, reason: '"$wrong" açmamalı');
      }
      expect(setCalls, isEmpty);

      final f = FallEnableFlow(s);
      await f.begin();
      await f.onReply('evet');
      final cancel = await f.onReply('tamam');
      expect(cancel, isA<CancelStep>());
      expect((cancel as CancelStep).message, Tr.fallOpenNotEnabled);
      expect(s.pending, isFalse, reason: 'ikinci yanlış cevapta bekleyen de iptal');
      expect(setCalls, isEmpty);
    });

    test('ipucundan sonra doğru cümle yine açar', () async {
      final f = FallEnableFlow(session());
      await f.begin();
      await f.onReply('evet');
      final done = await f.onReply('onaylıyorum aç') as FinishStep;
      expect(done.result.success, isTrue);
      expect(mode, FallMode.on);
    });

    test('kapı tutmazsa: neden söylenir, uyarı okunmaz, bekleyen yok', () async {
      Future<String> reason() async {
        final step = await FallEnableFlow(session()).begin();
        expect(step, isA<FinishStep>());
        final result = (step as FinishStep).result;
        expect(result.success, isFalse);
        return result.message;
      }

      direct = false;
      expect(await reason(), Tr.fallOpenBlockedBuild);
      direct = true;
      contacts = 0;
      expect(await reason(), Tr.fallOpenBlockedNoContacts);
      contacts = 1;
      sms = false;
      expect(await reason(), Tr.fallOpenBlockedNoSms);
      sms = true;
      since = now.subtract(const Duration(days: 3));
      expect(await reason(), Tr.fallOpenBlockedShadow(4));
      expect(setCalls, isEmpty);
    });

    test('zaten açıksa bilgi verir', () async {
      mode = FallMode.on;
      final step = await FallEnableFlow(session()).begin() as FinishStep;
      expect(step.result.message, Tr.fallOpenAlready);
      expect(step.result.success, isTrue);
    });

    test('onay anında kapı bozulmuşsa (acil kişi silindi) açmaz ve nedenini söyler', () async {
      final f = FallEnableFlow(session());
      await f.begin();
      contacts = 0;
      final done = await f.onReply('anladım aç') as FinishStep;
      expect(done.result.success, isFalse);
      expect(done.result.message, Tr.fallOpenBlockedNoContacts);
      expect(mode, FallMode.shadow);
      expect(state.heard, isFalse);
    });

    test('süre dolduktan sonra "anladım aç" açmaz', () {
      fakeAsync((async) {
        final f = FallEnableFlow(session());
        f.begin();
        async.flushMicrotasks();
        async.elapse(FallEnableSession.timeout);
        DialogStep? step;
        f.onReply('anladım aç').then((s) => step = s);
        async.flushMicrotasks();
        expect((step as FinishStep).result.message, Tr.fallOpenExpired);
        expect(mode, FallMode.shadow);
      });
    });

    test('ekran kanalı bekleyense sesle onay açmaz', () async {
      final s = session();
      await s.begin(FallEnableChannel.screen);
      final f = FallEnableFlow(s);
      // Sesli akışın begin'i ekranın bekleyenini geçersiz kılar; eski kanal onaylayamaz.
      await f.begin();
      expect(s.pendingChannel, FallEnableChannel.voice);
      expect((await s.confirm(FallEnableChannel.screen)).kind, FallEnableConfirmKind.wrongChannel);
      expect(setCalls, isEmpty);
    });

    test('7 gün kapısı debug\'da atlanırsa uyarının başında söylenir (iz)', () async {
      since = null;
      final step =
          await FallEnableFlow(session(policy: const ShadowGatePolicy(debugSkip: true))).begin() as AskStep;
      expect(step.prompt, startsWith(Tr.fallGateBypassedNote));
    });
  });

  group('FallHandler', () {
    late FallMode mode;
    late List<FallMode> setCalls;

    setUp(() {
      mode = FallMode.off;
      setCalls = [];
    });

    // Diyalog gerektirmeyen komutlar için: DialogManager'a gerek yok, ama
    // handler hepsini ister; uygulamanınkini kullanırız.
    FallHandler handlerWith(Harness h) => FallHandler(
          session: FallEnableSession(
            gate: FallOpenModeGate(
              directBuild: () async => true,
              contactCount: () async => 1,
              hasSmsPermission: () async => true,
              shadowSince: () async => DateTime.now().subtract(const Duration(days: 9)),
            ),
            state: MemoryFallOpenState(),
            consent: MemoryFallConsentStore(),
            currentMode: () => mode,
            setMode: (m) async {
              setCalls.add(m);
              mode = m;
            },
          ),
          dialogs: h.app.dialogs,
          mode: () => mode,
          setMode: (m) async {
            setCalls.add(m);
            mode = m;
          },
        );

    test('bağlanmamışsa (bağımlılık yok) komut kullanılamıyor der, hiçbir şey yapmaz', () async {
      final result = await FallHandler().handle('ac');
      expect(result.success, isFalse);
      expect(result.message, Tr.fallCommandUnavailable);
      expect((await FallHandler().handle('kapat')).message, Tr.fallCommandUnavailable);
    });

    test('router DUSME niyetini handler\'a yollar', () async {
      final result = await CommandRouter().route(BleCommand.fromWire('DUSME', 'durum'));
      expect(result.message, Tr.fallCommandUnavailable, reason: 'varsayılan handler bağlı değil');
    });

    test('kapat: açıkken de tek adımda tamamen kapanır; kapalıyken zararsız', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        mode = FallMode.on;
        handler.handle('kapat').then((r) {
          expect(r.message, Tr.fallShadowDisabled);
        });
        async.flushMicrotasks();
        expect(mode, FallMode.off);
        expect(setCalls, [FallMode.off]);

        handler.handle('golge_kapat').then((r) => expect(r.message, Tr.fallOffAlready));
        async.flushMicrotasks();
        expect(setCalls, [FallMode.off], reason: 'kapalıyken tekrar yazılmadı');
        h.dispose();
      });
    });

    test('gölge aç: kapalıyken açar (uyarı okunur); gölgedeyse bilgi; açıktayken açık modu DEĞİŞTİRMEZ', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        handler.handle('golge_ac').then((r) => expect(r.message, Tr.fallShadowWarning));
        async.flushMicrotasks();
        expect(mode, FallMode.shadow);

        handler.handle('golge_ac').then((r) => expect(r.message, Tr.fallShadowAlready));
        async.flushMicrotasks();

        mode = FallMode.on;
        setCalls.clear();
        handler.handle('golge_ac').then((r) => expect(r.message, Tr.fallShadowWhileOpen));
        async.flushMicrotasks();
        expect(mode, FallMode.on);
        expect(setCalls, isEmpty);
        h.dispose();
      });
    });

    test('durum: moda göre tek cümle', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        final said = <String>[];
        for (final m in FallMode.values) {
          mode = m;
          handler.handle('durum').then((r) => said.add(r.message));
        }
        async.flushMicrotasks();
        expect(said, [Tr.statusFallOff, Tr.statusFallShadow, Tr.statusFallOn]);
        h.dispose();
      });
    });

    test('bilinmeyen entity: anlaşılmadı', () {
      fakeAsync((async) {
        final h = Harness();
        handlerWith(h).handle('x').then((r) => expect(r.success, isFalse));
        async.flushMicrotasks();
        expect(mode, FallMode.off);
        h.dispose();
      });
    });

    test('"ac" modu kendisi asla on yapmaz: yalnızca diyalog başlatır', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        handler.handle('ac');
        async.flushMicrotasks();
        expect(h.app.dialogs.active, isTrue);
        expect(mode, FallMode.off);
        expect(setCalls, isEmpty);
        h.dispose();
      });
    });

    test('uçtan uca: ses komutu -> uyarı -> "evet" açmaz -> "anladım aç" açar', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        mode = FallMode.shadow;
        handler.handle('ac');
        async.flushMicrotasks();
        h.speakAll(async);
        expect(h.tts.spoken.last, contains(Tr.fallOpenWarningFull));
        expect(mode, FallMode.shadow);

        answer(h, async, 'evet');
        expect(mode, FallMode.shadow);
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.fallOpenConfirmHint);

        answer(h, async, 'anladım, aç');
        h.speakAll(async);
        expect(mode, FallMode.on);
        expect(h.tts.spoken.last, contains(Tr.fallOpenEnabled));
        h.dispose();
      });
    });

    test('uçtan uca: "vazgeç" açmayı bitirir, mod değişmez', () {
      fakeAsync((async) {
        final h = Harness();
        final handler = handlerWith(h);
        mode = FallMode.shadow;
        handler.handle('ac');
        async.flushMicrotasks();
        answer(h, async, 'vazgeç');
        h.speakAll(async);
        expect(h.app.dialogs.active, isFalse);
        expect(mode, FallMode.shadow);
        expect(setCalls, isEmpty);
        h.dispose();
      });
    });
  });

  test('komutlar listesi (yardım ayrıntısı) düşme algılama komutlarını söyler', () {
    expect(Tr.helpDetail, contains('düşme algılamayı aç'));
    expect(Tr.helpDetail, contains('düşme algılamayı kapat'));
  });

  group('metin', () {
    String section() {
      final source = File('lib/l10n/strings_tr.dart').readAsStringSync();
      final start = source.indexOf('// --- Düşme algılama: açık mod (Faz 7c-2)');
      expect(start, greaterThanOrEqualTo(0));
      final next = source.indexOf('\n  // --- ', start + 10);
      final code = source
          .substring(start, next == -1 ? source.length : next)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      return code;
    }

    test('açık mod metinlerinde hiçbir güvence sözcüğü yok (güvenli, kesin, garanti)', () {
      final literals =
          RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(section()).map((m) => m.group(1)!).toList();
      expect(literals, isNotEmpty);
      const assurances = {'güvenli', 'güvenle', 'kesin', 'kesinlikle', 'garanti', 'garantili'};
      for (final text in literals) {
        final words = text.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true));
        expect(words.where(assurances.contains), isEmpty, reason: '"$text"');
      }
    });

    test('tam uyarı: deneysel, her düşmeyi algılamayabilir, güvenilmemeli, 112 kendiliğinden aranmaz, servis değil', () {
      const t = Tr.fallOpenWarningFull;
      expect(t, contains('deneysel'));
      expect(t, contains('her düşmeyi algılamayabilir'));
      expect(t, contains('güvenilmemelidir'));
      expect(t, contains('112 kendiliğinden aranmaz'));
      expect(t, contains('Patika acil durum servisi değildir'));
    });

    test('kısa hatırlatma: "Düşme algılama deneysel, hâlâ güvenilmemeli"', () {
      expect(Tr.fallOpenWarningShort, startsWith('Düşme algılama deneysel, hâlâ güvenilmemeli'));
    });

    test('ses kanalı yönergesi tam kalıbı söyler; "evet yetmez" denir', () {
      expect(Tr.fallOpenConfirmInstruction, contains('anladım, aç'));
      expect(Tr.fallOpenConfirmHint, contains('evet yetmez'));
    });
  });

  test('kaynak kodu: diyalog ve handler modu doğrudan on yapmaz (yalnızca oturum)', () {
    for (final path in [
      'lib/voice/dialogs/fall_enable_flow.dart',
      'lib/commands/handlers/fall_handler.dart',
    ]) {
      final code = File(path)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp(r'setMode\(\s*FallMode\.on').hasMatch(code), isFalse, reason: path);
    }
  });
}
