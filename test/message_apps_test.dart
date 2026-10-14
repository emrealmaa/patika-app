import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_command.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/screens/settings_screen.dart';
import 'package:patika_app/settings/message_apps.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/theme/app_theme.dart';

import 'fakes.dart';
import 'navigation_language_test.dart' show bannedIn;
import 'test_harness.dart';

/// Madde 4: hangi uygulamaların mesaj bildirimi okunur. Varsayılan eski
/// davranış (SMS + WhatsApp), sabit beyaz liste, ses + ekran, hepsi kapanınca
/// sesli uyarı, "bildirimleri sustur" ile etkileşim bozulmaz.
void main() {
  IncomingMessage msg(String pkg) =>
      IncomingMessage(senderName: 'Ayşe Demir', body: 'merhaba', appPackage: pkg);

  group('ayar modeli', () {
    test('varsayılan Faz 4b davranışı: SMS + WhatsApp (kişisel + iş)', () {
      expect(const Settings().messageApps,
          {MessageApp.sms, MessageApp.whatsapp, MessageApp.whatsappBusiness});
    });

    test('JSON gidiş-dönüş; bilinmeyen uygulama adı atılır; eski kayıt varsayılana düşer', () {
      final s = const Settings().copyWith(messageApps: {MessageApp.telegram});
      expect(Settings.fromJson(s.toJson()), s);
      final json = s.toJson()..['messageApps'] = ['telegram', 'com.rastgele.uygulama', 42];
      expect(Settings.fromJson(json).messageApps, {MessageApp.telegram});
      expect(Settings.fromJson(const {}).messageApps, MessageApp.defaults);
    });

    test('native beyaz listesi Dart listesiyle aynı', () {
      final kotlin = File('android/app/src/main/kotlin/com/patika/patika_app/PatikaNotificationListener.kt')
          .readAsStringSync();
      final block = RegExp(r'KNOWN_PACKAGES = setOf\(([^)]*)\)').firstMatch(kotlin)!.group(1)!;
      final native = RegExp(r'"([^"]+)"').allMatches(block).map((m) => m.group(1)).toSet();
      expect(native, {for (final a in MessageApp.values) if (a.package != null) a.package});
    });
  });

  group('sesli komut', () {
    BleCommand c(String s) => classifyVoiceCommand(s);

    test('"WhatsApp bildirimlerini kapat" yalnızca WhatsApp', () {
      final cmd = c("WhatsApp'ın bildirimlerini kapat");
      expect(cmd.intent, PatikaIntent.ayar);
      expect(parseMessageAppEntity(cmd.entity), (MessageApp.whatsapp, false));
      expect(parseMessageAppEntity(c('sms bildirimlerini aç').entity), (MessageApp.sms, true));
      expect(parseMessageAppEntity(c('telegram bildirimlerini aç').entity), (MessageApp.telegram, true));
    });

    test('"mesaj uygulamaları" listeyi sorar; genel "bildirimleri kapat" değişmedi', () {
      expect(c('mesaj uygulamaları').entity, messageAppsListEntity);
      expect(c('bildirimleri kapat').entity, SettingAction.notificationsMuteOn.name);
      expect(c("WhatsApp'ı aç").entity, isNot(startsWith('mesajUygulamasi')));
    });
  });

  group('uygulamada', () {
    test('WhatsApp kapatılınca (iki paket) mesajı okunmaz, günlüğe girmez; SMS sürer', () {
      fakeAsync((async) {
        final messages = FakeIncomingMessages();
        final pushed = <Set<MessageApp>>[];
        final h = Harness(incomingMessages: messages, pushWatchedApps: (apps) async => pushed.add(apps));
        async.flushMicrotasks();
        expect(pushed.single, MessageApp.defaults, reason: 'açılışta native\'e gider');

        h.app.submitVoiceCommand(classifyVoiceCommand('whatsapp bildirimlerini kapat'));
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.messageAppOff('WhatsApp'));
        expect(h.settings.value.messageApps, {MessageApp.sms});
        expect(pushed.last, {MessageApp.sms});

        h.tts.spoken.clear();
        messages.emit(msg('com.whatsapp'));
        messages.emit(msg('com.whatsapp.w4b'));
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty);
        messages.emit(msg('com.google.android.apps.messaging'));
        h.speakAll(async);
        expect(h.tts.spoken.join(), contains('merhaba'));
        h.dispose();
      });
    });

    test('hepsi kapanınca "mesaj duyuruları kapalı" denir', () {
      fakeAsync((async) {
        final h = Harness(pushWatchedApps: (_) async {});
        h.app.submitVoiceCommand(classifyVoiceCommand('whatsapp bildirimlerini kapat'));
        h.app.submitVoiceCommand(classifyVoiceCommand('sms bildirimlerini kapat'));
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.messageAppsAllOff);
        h.app.submitVoiceCommand(classifyVoiceCommand('mesaj uygulamaları'));
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.messageAppsAllOff);
        h.dispose();
      });
    });

    test('liste okunur', () {
      fakeAsync((async) {
        final h = Harness(pushWatchedApps: (_) async {});
        h.app.submitVoiceCommand(classifyVoiceCommand('mesaj uygulamaları'));
        h.speakAll(async);
        expect(h.tts.spoken.last, Tr.messageAppsList(['SMS', 'WhatsApp', 'WhatsApp Business']));
        h.dispose();
      });
    });

    test('"bildirimleri sustur" ile etkileşim: izlenen mesaj günlüğe girer ama okunmaz', () {
      fakeAsync((async) {
        final messages = FakeIncomingMessages();
        final h = Harness(
          incomingMessages: messages,
          initial: const Settings(notificationsMuted: true),
          pushWatchedApps: (_) async {},
        );
        messages.emit(msg('com.whatsapp'));
        h.speakAll(async);
        expect(h.tts.spoken, isEmpty);
        h.app.submitVoiceCommand(classifyVoiceCommand('mesajlarımı oku'));
        h.speakAll(async);
        expect(h.tts.spoken.join(), contains('merhaba'));
        h.dispose();
      });
    });
  });

  testWidgets('Ayarlar: her uygulama için anahtar; sonuncusu kapanınca sesli uyarı', (tester) async {
    tester.view.physicalSize = const Size(1080, 16000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final h = Harness(pushWatchedApps: (_) async {});
    addTearDown(h.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SettingsScreen(store: h.settings, feedback: h.app.feedback, onStartTutorial: () {})),
    ));
    for (final a in MessageApp.values) {
      expect(find.widgetWithText(SwitchListTile, Tr.messageAppName(a.name)), findsOneWidget);
    }
    for (final a in [MessageApp.sms, MessageApp.whatsapp, MessageApp.whatsappBusiness]) {
      await tester.tap(find.widgetWithText(SwitchListTile, Tr.messageAppName(a.name)));
      await tester.pump();
    }
    expect(h.settings.value.messageApps, isEmpty);
    expect(h.tts.spoken.last, Tr.messageAppsAllOff);
    final tile = tester.getSize(find.widgetWithText(SwitchListTile, 'Telegram'));
    expect(tile.height, greaterThanOrEqualTo(56));
  });

  test('metinler yasaklı kelime içermez', () {
    for (final t in [
      Tr.messageAppsSection,
      Tr.messageAppsAllOff,
      Tr.messageAppOn('WhatsApp'),
      Tr.messageAppOff('WhatsApp'),
      Tr.messageAppsList(['SMS']),
    ]) {
      expect(bannedIn(t), isEmpty, reason: t);
    }
  });
}
