import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bildirimden yakalanan bir mesaj (Faz 4b) - `PatikaNotificationListener.kt`
/// yalnızca izlenen uygulamalardan (varsayılan SMS + WhatsApp) gelenleri
/// gönderir.
class IncomingMessage {
  final String senderName;
  final String body;
  final String appPackage;

  const IncomingMessage({
    required this.senderName,
    required this.body,
    required this.appPackage,
  });
}

/// Bildirimden yakalanan mesajların akışı. Gerçek OS bildirimini simüle
/// etmenin bir anlamı yok (bkz. `DirectActions`) - yalnızca gerçek cihazda
/// test edilir.
abstract class IncomingMessages {
  Stream<IncomingMessage> get messages;
  void dispose();
}

class MethodChannelIncomingMessages implements IncomingMessages {
  static const _channel = MethodChannel('patika/notifications');
  final _controller = StreamController<IncomingMessage>.broadcast();

  MethodChannelIncomingMessages() {
    _channel.setMethodCallHandler(_onCall);
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'message') return;
    try {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final sender = args['senderName'] as String?;
      final body = args['body'] as String?;
      if (sender == null || body == null) return;
      _controller.add(IncomingMessage(
        senderName: sender,
        body: body,
        appPackage: args['appPackage'] as String? ?? '',
      ));
    } catch (e) {
      debugPrint('[Notifications] mesaj ayrıştırılamadı: $e');
    }
  }

  @override
  Stream<IncomingMessage> get messages => _controller.stream;

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}

/// Testlerde ve Android dışı platformlarda varsayılan.
class NoIncomingMessages implements IncomingMessages {
  const NoIncomingMessages();

  @override
  Stream<IncomingMessage> get messages => const Stream.empty();

  @override
  void dispose() {}
}

/// "Mesaj içerikleri yüksek sesle okunuyor" uyarısının bir kez söylenip
/// söylenmediği. Ayarlardan AYRI tutuluyor (bkz. `TutorialProgress`): ayar
/// kapatılıp yeniden açılsa da uyarı ikinci kez söylenmez - yalnızca
/// gerçekten ilk kez duyuruluyor.
abstract class LoudMessagesNotice {
  Future<bool> wasShown();
  Future<void> markShown();
}

class SharedPrefsLoudMessagesNotice implements LoudMessagesNotice {
  static const _key = 'patika.loudMessagesNoticeShown.v1';
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> wasShown() async {
    try {
      return await _prefs.getBool(_key) ?? false;
    } catch (e) {
      debugPrint('[Notifications] uyarı durumu okunamadı: $e');
      // Okunamıyorsa her seferinde uyarmaktansa atla.
      return true;
    }
  }

  @override
  Future<void> markShown() async {
    try {
      await _prefs.setBool(_key, true);
    } catch (e) {
      debugPrint('[Notifications] uyarı durumu kaydedilemedi: $e');
    }
  }
}

class MemoryLoudMessagesNotice implements LoudMessagesNotice {
  bool shown;

  MemoryLoudMessagesNotice([this.shown = false]);

  @override
  Future<bool> wasShown() async => shown;

  @override
  Future<void> markShown() async => shown = true;
}
