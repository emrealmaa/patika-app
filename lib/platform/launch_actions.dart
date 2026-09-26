import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android tarafından gelen başlatma talimatları (Hızlı Ayarlar karosu:
/// "dinle"). Talimat native tarafta bekletiliyor; Dart açılışta kendisi
/// soruyor, zaten çalışıyorsa "actionPending" bildirimiyle haberdar oluyor -
/// böylece ilk açılışta da, uygulama açıkken de kaybolmuyor
/// (bkz. MainActivity.handleLaunchIntent).
class LaunchActions {
  static const _channel = MethodChannel('patika/launch');

  final VoidCallback onListen;

  LaunchActions({required this.onListen});

  void attach() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'actionPending') await _consume();
    });
    _consume();
  }

  void detach() => _channel.setMethodCallHandler(null);

  Future<void> _consume() async {
    try {
      final action = await _channel.invokeMethod<String>('consumePendingAction');
      if (action == 'listen') onListen();
    } on MissingPluginException {
      // Android dışı platform ya da testler - talimat kanalı yok.
    } catch (e) {
      debugPrint('[Launch] talimat alınamadı: $e');
    }
  }
}
