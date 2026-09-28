import 'dart:async';

import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/accessibility/speech_output.dart';
import 'package:patika_app/navigation/geo.dart';
import 'package:patika_app/navigation/place_search.dart';
import 'package:patika_app/navigation/route.dart';
import 'package:patika_app/navigation/route_planner.dart';
import 'package:patika_app/permissions/location_access.dart';
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
///
/// **Testte gerçek 112 hiçbir yolla aranamaz**: 112'ye giden her arama/SMS
/// anında hata fırlatır (asılsız 112 aramasının idari para cezası var; bkz.
/// CLAUDE.md Faz 7 kararları). SOS testleri sahte bir test numarası kullanır.
class FakeDirectActions implements DirectActions {
  bool available = true;
  bool callSucceeds = true;
  SmsSendStatus smsResult = SmsSendStatus.sent;
  final calls = <String>[];
  final sms = <(String, String)>[];

  static void _refuseReal112(String number) {
    if (number.replaceAll(RegExp(r'\D'), '') == '112') {
      throw StateError('Testte gerçek 112 aranamaz');
    }
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> call(String number) async {
    _refuseReal112(number);
    calls.add(number);
    return callSucceeds;
  }

  @override
  Future<SmsSendStatus> sendSms(String number, String body) async {
    _refuseReal112(number);
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

/// Konum izninin sahte hali: [granted] elle ayarlanır, [requests] kaç kez
/// açıklamalı istendiğini sayar.
class FakeLocationAccess implements LocationAccess {
  bool granted;
  bool grantOnRequest;
  int requests = 0;
  FakeLocationAccess({this.granted = false, this.grantOnRequest = true});

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> requestWithExplanation() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }
}

/// Rota hesaplayıcının sahte hali: [result] verilir, [fail] açıksa hata fırlatır.
class FakePlanner implements RoutePlanner {
  final calls = <({LatLng from, LatLng to, String name})>[];
  WalkingRoute? result;
  bool fail = false;

  @override
  Future<WalkingRoute> plan({
    required LatLng from,
    required LatLng to,
    required String destinationName,
  }) async {
    calls.add((from: from, to: to, name: destinationName));
    if (fail || result == null) throw const RoutePlanException('hesaplanamadı');
    return result!;
  }
}

/// Yer aramasının sahte hali: [results] döner, [fail] açıksa hata fırlatır.
class FakePlaceSearch implements PlaceSearch {
  List<PlaceCandidate> results;
  bool fail = false;
  final calls = <({String query, LatLng? near})>[];

  FakePlaceSearch([this.results = const []]);

  @override
  Future<List<PlaceCandidate>> search(String query, {LatLng? near}) async {
    calls.add((query: query, near: near));
    if (fail) throw const PlaceSearchException('arama başarısız');
    return results;
  }
}
