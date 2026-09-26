import 'dart:async';

import 'package:patika_app/accessibility/earcons.dart';
import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/accessibility/speech_output.dart';

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
