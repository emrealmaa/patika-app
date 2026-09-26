import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SmsSendStatus { sent, failed, timeout, unavailable }

/// Onaydan sonra doğrudan arama / SMS (Faz 4a). Yalnızca "direct" derleme
/// türünde etkin (bkz. android/app/build.gradle.kts); "play" türünde
/// [isAvailable] false döner ve handler'lar eski akışa (arama/SMS ekranını
/// açma) düşer.
abstract class DirectActions {
  Future<bool> isAvailable();
  Future<bool> call(String number);
  Future<SmsSendStatus> sendSms(String number, String body);
}

class MethodChannelDirectActions implements DirectActions {
  static const _channel = MethodChannel('patika/direct');
  bool? _available;

  @override
  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      return _available = await _channel.invokeMethod<bool>('available') ?? false;
    } catch (e) {
      // Android dışı platform ya da testler.
      debugPrint('[Direct] sorgulanamadı: $e');
      return _available = false;
    }
  }

  @override
  Future<bool> call(String number) async {
    try {
      return await _channel.invokeMethod<bool>('call', {'number': number}) ?? false;
    } catch (e) {
      debugPrint('[Direct] arama başlatılamadı: $e');
      return false;
    }
  }

  @override
  Future<SmsSendStatus> sendSms(String number, String body) async {
    try {
      final status = await _channel.invokeMethod<String>('sendSms', {
        'number': number,
        'body': body,
      });
      debugPrint('[Direct] SMS sonucu: $status');
      return switch (status) {
        'sent' => SmsSendStatus.sent,
        'timeout' => SmsSendStatus.timeout,
        'unavailable' => SmsSendStatus.unavailable,
        _ => SmsSendStatus.failed,
      };
    } catch (e) {
      debugPrint('[Direct] SMS gönderilemedi: $e');
      return SmsSendStatus.failed;
    }
  }
}

/// Doğrudan eylem yok ("play" türü gibi) - varsayılan ve testler.
class NoDirectActions implements DirectActions {
  const NoDirectActions();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> call(String number) async => false;

  @override
  Future<SmsSendStatus> sendSms(String number, String body) async => SmsSendStatus.unavailable;
}
