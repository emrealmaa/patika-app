import 'dart:async';

import 'call_service.dart';

/// Gelen aramayı simüle eder (Test Modu). Üstteki zincir (duyuru, gözlük
/// dokunma/uzun basış davranışı, arama sırasında susma) gerçek telefon durumu
/// olmadan denenebilir. Açılan arama [endCall] ile biter.
class SimulatedCallService implements PatikaCallService {
  final _controller = StreamController<IncomingCall?>.broadcast();
  final _state = StreamController<PhoneCallState>.broadcast();
  IncomingCall? _current;
  PhoneCallState _phase = PhoneCallState.idle;

  @override
  Stream<IncomingCall?> get incomingCall => _controller.stream;

  @override
  Stream<PhoneCallState> get callState => _state.stream;

  @override
  PhoneCallState get currentState => _phase;

  @override
  bool get canAnswer => true;

  /// Test ekranındaki durum göstergesi için.
  IncomingCall? get current => _current;

  @override
  Future<bool> start() async => true;

  /// Test ekranı: "$callerName arıyor" simülasyonu başlatır. Zaten çalan bir
  /// arama varsa onun yerine geçer.
  void startCall(String callerName, {String? number, CallerKind kind = CallerKind.named}) {
    _current = IncomingCall(callerName: callerName, number: number, kind: kind);
    _setPhase(PhoneCallState.ringing);
    if (!_controller.isClosed) _controller.add(_current);
  }

  @override
  Future<bool> answer() async {
    if (_current == null) return false;
    _clear();
    _setPhase(PhoneCallState.offhook);
    return true;
  }

  @override
  Future<bool> reject() async {
    if (_current == null) return false;
    _clear();
    _setPhase(PhoneCallState.idle);
    return true;
  }

  /// Açılmış aramanın (ya da çalan aramanın) bitmesi.
  void endCall() {
    _clear();
    _setPhase(PhoneCallState.idle);
  }

  void _clear() {
    if (_current == null) return;
    _current = null;
    if (!_controller.isClosed) _controller.add(null);
  }

  void _setPhase(PhoneCallState phase) {
    if (_phase == phase) return;
    _phase = phase;
    if (!_state.isClosed) _state.add(phase);
  }

  @override
  void dispose() {
    _controller.close();
    _state.close();
  }
}
