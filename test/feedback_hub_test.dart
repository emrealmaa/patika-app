import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/feedback_hub.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/commands/action_result.dart';
import 'package:patika_app/settings/settings.dart';

import 'fakes.dart';

void main() {
  late FakeSpeechOutput tts;
  late FakeHaptics haptics;
  late FakeEarcons earcons;
  late Settings settings;
  late FeedbackHub hub;

  setUp(() {
    tts = FakeSpeechOutput();
    haptics = FakeHaptics();
    earcons = FakeEarcons();
    settings = const Settings();
    hub = FeedbackHub(
      queue: AnnouncementQueue(tts),
      haptics: haptics,
      earcons: earcons,
      settings: () => settings,
    );
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('sonuç hem sesle hem titreşimle hem kısa sesle bildirilir', () async {
    hub.result(ActionResult.ok('Saat 14:05'));
    await settle();
    expect(tts.spoken, ['Saat 14:05']);
    expect(haptics.played.single.$1, HapticPatternId.understood);
    expect(earcons.played, [Earcon.success]);
  });

  test('hata sonucu hata titreşimi ve hata sesiyle bildirilir', () async {
    hub.result(ActionResult.fail('Bu komutu anlayamadım'));
    await settle();
    expect(haptics.played.single.$1, HapticPatternId.error);
    expect(earcons.played, [Earcon.error]);
  });

  test('uzun ayrıntıda açıklama da okunur, kısada okunmaz', () async {
    final r = ActionResult.ok('Ali için arama ekranı açıldı', detail: 'Arama tuşuna basın.');
    expect(FeedbackHub.spokenResult(r, Verbosity.long),
        'Ali için arama ekranı açıldı. Arama tuşuna basın.');
    expect(FeedbackHub.spokenResult(r, Verbosity.short), 'Ali için arama ekranı açıldı');
  });

  test('sadece kısa ses modunda durum sözü okunmaz, içerik okunur', () async {
    settings = const Settings(feedbackMode: FeedbackMode.earconOnly);
    hub.signal(FeedbackEvent.listening, statusText: 'Dinliyorum');
    await settle();
    expect(tts.spoken, isEmpty);
    expect(earcons.played, [Earcon.listenStart]);

    hub.signal(FeedbackEvent.understood, text: 'Şunu anladım: saat kaç');
    await settle();
    expect(tts.spoken, ['Şunu anladım: saat kaç']);
  });

  test('sesli bildirim modunda durum sözü okunur', () async {
    settings = const Settings(feedbackMode: FeedbackMode.speech);
    hub.signal(FeedbackEvent.listening, statusText: 'Dinliyorum');
    await settle();
    expect(tts.spoken, ['Dinliyorum']);
  });

  test('sessiz sonuç okunmaz ama titreşimle bildirilir', () async {
    hub.result(ActionResult.silentOk('Durduruldu'));
    await settle();
    expect(tts.spoken, isEmpty);
    expect(haptics.played.single.$1, HapticPatternId.understood);
  });

  test('durum sözü "tekrar et" ile tekrarlanacak son duyuru sayılmaz', () async {
    settings = const Settings(feedbackMode: FeedbackMode.speech);
    hub.say('Saat 14:05');
    await settle();
    tts.finishCurrent();
    await settle();
    hub.signal(FeedbackEvent.listening, statusText: 'Dinliyorum');
    await settle();
    expect(hub.queue.lastSpoken, 'Saat 14:05');
  });

  test('kısa sesi olmayan olayın durum sözü kısa ses modunda da okunur', () async {
    settings = const Settings(feedbackMode: FeedbackMode.earconOnly);
    hub.signal(FeedbackEvent.disconnected, statusText: 'Gözlük bağlantısı koptu');
    await settle();
    expect(tts.spoken, ['Gözlük bağlantısı koptu']);
  });

  test('titreşim şiddeti ayardan uygulanır', () async {
    settings = const Settings(hapticLevel: 1);
    hub.signal(FeedbackEvent.connected);
    expect(haptics.played.single.$2, Settings.hapticScales[1]);
  });

  test('bağlantı duyurusu komut sonucunu keser (high > normal)', () async {
    hub.result(ActionResult.ok('Uzun bir komut sonucu'));
    await settle();
    hub.signal(FeedbackEvent.disconnected,
        text: 'Gözlük bağlantısı koptu', priority: AnnouncementPriority.high);
    await settle();
    expect(tts.stops, 1);
    expect(tts.spoken.last, 'Gözlük bağlantısı koptu');
  });
}
