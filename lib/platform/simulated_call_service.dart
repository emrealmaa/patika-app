import 'dart:async';

import 'call_service.dart';

/// Bildirim dinleyici (`PatikaNotificationListener.kt`) henüz yokken gelen
/// aramayı simüle eder. Test ekranındaki "gelen arama simülasyonu" bunu
/// çağırır; üstteki zincir (duyuru, gözlük dokunma/uzun basış davranışı)
/// gerçek telefon durumu olmadan denenebilir.
class SimulatedCallService implements PatikaCallService {
  final _controller = StreamController<IncomingCall?>.broadcast();
  IncomingCall? _current;

  @override
  Stream<IncomingCall?> get incomingCall => _controller.stream;

  /// Test ekranındaki durum göstergesi için.
  IncomingCall? get current => _current;

  /// Test ekranı: "$callerName arıyor" simülasyonu başlatır. Zaten çalan bir
  /// arama varsa onun yerine geçer.
  void startCall(String callerName, {String? number}) {
    _current = IncomingCall(callerName: callerName, number: number);
    if (!_controller.isClosed) _controller.add(_current);
  }

  @override
  Future<void> answer() async => _end();

  @override
  Future<void> reject() async => _end();

  void _end() {
    if (_current == null) return;
    _current = null;
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  void dispose() => _controller.close();
}
