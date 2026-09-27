import 'dart:async';

import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/accessibility/speech_output.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/platform/notification_access.dart';
import 'package:patika_app/voice/speech_input_service.dart';

/// Konuşmayı test kontrol etsin diye her speak() açık bir Completer döner;
/// [finishCurrent] ile "konuşma bitti" denir. stop() mevcut konuşmayı da
/// bitirir (gerçek TTS'teki gibi).
class FakeSpeechOutput implements SpeechOutput {
  final List<String> spoken = [];
  int stops = 0;
  double? rate;
  double? pitch;
  Completer<void>? _current;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  void finishCurrent() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finishCurrent();
  }

  @override
  Future<void> configure({required double rate, required double pitch}) async {
    this.rate = rate;
    this.pitch = pitch;
  }
}

/// Konuşma tanıma: test "kullanıcı şunu söyledi" ([say]) ya da hata/sessizlik
/// ([fail], [done]) taklit eder.
class FakeSpeechInput implements SpeechInput {
  bool ready = true;
  int initCalls = 0;
  int cancelCalls = 0;
  bool listening = false;
  Duration? lastSilenceTimeout;
  bool lastDictation = false;
  void Function(String)? _onFinal;
  void Function(String)? _onError;
  void Function()? _onDone;

  @override
  Future<bool> init() async {
    initCalls++;
    return ready;
  }

  @override
  Future<void> listen({
    required void Function(String text) onFinal,
    required void Function(String message) onError,
    required void Function() onDone,
    Duration silenceTimeout = const Duration(seconds: 3),
    bool dictation = false,
  }) async {
    listening = true;
    lastSilenceTimeout = silenceTimeout;
    lastDictation = dictation;
    _onFinal = onFinal;
    _onError = onError;
    _onDone = onDone;
  }

  /// Oturumun geri çağırmaları önce yerele alınıyor: onFinal yeni bir
  /// dinleme başlatırsa (diyalogdaki sıradaki soru), eski oturumun "bitti"
  /// sinyali yeni oturuma gitmesin - gerçek tanıyıcıdaki gibi.
  void say(String text) {
    final onFinal = _onFinal, onDone = _onDone;
    listening = false;
    onFinal?.call(text);
    onDone?.call();
  }

  void fail(String message) {
    final onError = _onError, onDone = _onDone;
    listening = false;
    onError?.call(message);
    onDone?.call();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    listening = false;
  }
}

/// "direct" derleme türünün sahte hali: aramalar/SMS'ler kaydedilir.
class FakeDirectActions implements DirectActions {
  bool available = true;
  bool callSucceeds = true;
  SmsSendStatus smsResult = SmsSendStatus.sent;
  final calls = <String>[];
  final sms = <(String, String)>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> call(String number) async {
    calls.add(number);
    return callSucceeds;
  }

  @override
  Future<SmsSendStatus> sendSms(String number, String body) async {
    sms.add((number, body));
    return smsResult;
  }
}

/// Bildirim dinleyici erişiminin sahte hali: [enabled] elle ayarlanır,
/// [openSettingsCalls] kaç kez ayarların açıldığını sayar.
class FakeNotificationAccess implements NotificationAccess {
  bool enabled = false;
  int openSettingsCalls = 0;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}

/// Bildirimden gelen mesajların sahte hali: [emit] testte "şu mesaj geldi"
/// demek için.
class FakeIncomingMessages implements IncomingMessages {
  final _controller = StreamController<IncomingMessage>.broadcast();

  @override
  Stream<IncomingMessage> get messages => _controller.stream;

  void emit(IncomingMessage message) => _controller.add(message);

  @override
  void dispose() => _controller.close();
}

class FakeHaptics implements HapticOutput {
  final List<(HapticPatternId, double)> played = [];
  double? obstacle;

  @override
  Future<void> play(HapticPatternId id, {required double scale}) async =>
      played.add((id, scale));

  @override
  void updateObstacle(double? distanceMeters, {required double scale}) =>
      obstacle = distanceMeters;
}

class FakeEarcons implements EarconPlayer {
  final List<Earcon> played = [];

  @override
  Future<void> play(Earcon earcon) async => played.add(earcon);
}
