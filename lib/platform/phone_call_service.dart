import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../contacts/contact_matcher.dart';
import 'call_service.dart';

/// Arama ekranı bildiriminin başlığından arayan: numara gibi görünen başlık
/// (harf yok, en az 3 rakam) "bilinmeyen numara"dır; numara hiçbir zaman
/// seslendirilmez. Ad rehberde bulunursa rehberdeki ad, birden çok aday
/// varsa arama ekranının gösterdiği ad, hiç yoksa "bilinmeyen numara".
/// [match] null: rehber okunamadı (izin yok) - arama ekranının adı kullanılır
/// (o adı zaten telefonun kendi rehberi çözmüştür).
IncomingCall identifyCaller(String? hint, ContactMatch? match) {
  final title = hint?.trim() ?? '';
  if (title.isEmpty) {
    return const IncomingCall(callerName: '', kind: CallerKind.unidentified);
  }
  if (looksLikePhoneNumber(title)) {
    return const IncomingCall(callerName: '', kind: CallerKind.unknownNumber);
  }
  return switch (match) {
    ContactFound(:final contact) => IncomingCall(callerName: contact.displayName),
    ContactAmbiguous() || ContactPermissionDenied() || null => IncomingCall(callerName: title),
    ContactNotFound() => const IncomingCall(callerName: '', kind: CallerKind.unknownNumber),
  };
}

bool looksLikePhoneNumber(String s) =>
    !RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ]').hasMatch(s) && RegExp(r'\d').allMatches(s).length >= 3;

/// Gerçek gelen arama (Android): durum `CallStateProbe.kt`'ten (kanal
/// `patika/call_state`, `READ_PHONE_STATE`), arayan adı
/// `PatikaNotificationListener.kt`'in yakaladığı arama bildiriminden
/// (`callerHint`; bildirim erişimi yoksa gelmez). Aç/reddet
/// `TelecomManager.acceptRingingCall` / `endCall` (`ANSWER_PHONE_CALLS`).
///
/// Çalma genelde bildirimden önce gelir: ad için en fazla [hintWait]
/// beklenir, sonra eldeki bilgiyle duyurulur (duyuru tek seferlik).
class MethodChannelCallService implements PatikaCallService {
  static const channelName = 'patika/call_state';
  final MethodChannel _channel;

  /// Arayan bildirimi için bekleme.
  final Duration hintWait;

  /// Bildirim başlığını rehberle eşleştirir (izin İSTEMEZ; yoksa null).
  final Future<ContactMatch?> Function(String name) _match;

  MethodChannelCallService({
    required Future<ContactMatch?> Function(String name) match,
    this.hintWait = const Duration(milliseconds: 1500),
    MethodChannel channel = const MethodChannel(channelName),
  })  : _match = match,
        _channel = channel;

  final _calls = StreamController<IncomingCall?>.broadcast();
  final _states = StreamController<PhoneCallState>.broadcast();
  PhoneCallState _state = PhoneCallState.idle;
  bool _canAnswer = false;
  bool _handlerSet = false;

  /// Bu çalmada duyuru yapıldı mı / gelen ad.
  bool _announced = false;
  String? _hint;
  Timer? _hintTimer;
  IncomingCall? _current;

  @override
  Stream<IncomingCall?> get incomingCall => _calls.stream;

  @override
  Stream<PhoneCallState> get callState => _states.stream;

  @override
  PhoneCallState get currentState => _state;

  @override
  bool get canAnswer => _canAnswer;

  @override
  Future<bool> start() async {
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler(_onCall);
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('start');
      _canAnswer = result?['canAnswer'] == true;
      final active = result?['active'] == true;
      final state = _parseState(result?['state']);
      if (state != null) _onState(state);
      return active;
    } catch (e) {
      // iOS / testler: kanal yok.
      debugPrint('[Calls] arama durumu izlenemiyor: ${e.runtimeType}');
      return false;
    }
  }

  @visibleForTesting
  Future<void> handle(MethodCall call) => _onCall(call);

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onState':
        final state = _parseState(call.arguments);
        if (state != null) _onState(state);
      case 'callerHint':
        final args = call.arguments;
        final name = args is Map ? args['name'] as String? : null;
        if (name == null) return;
        _hint = name;
        if (_state == PhoneCallState.ringing && !_announced) await _announce();
    }
  }

  static PhoneCallState? _parseState(Object? raw) => switch (raw) {
        'idle' => PhoneCallState.idle,
        'ringing' => PhoneCallState.ringing,
        'offhook' => PhoneCallState.offhook,
        _ => null,
      };

  void _onState(PhoneCallState next) {
    if (next == _state) return;
    final previous = _state;
    _state = next;
    if (!_states.isClosed) _states.add(next);
    if (next == PhoneCallState.ringing) {
      _announced = false;
      // Bildirim çalmadan hemen ÖNCE geldiyse ad elde: kısa beklemeye gerek yok
      // ama yine de aynı yoldan (tek duyuru).
      _hintTimer?.cancel();
      _hintTimer = Timer(_hint == null ? hintWait : Duration.zero, () {
        if (_state == PhoneCallState.ringing && !_announced) _announce();
      });
    } else {
      _hintTimer?.cancel();
      _hint = null;
      if (previous == PhoneCallState.ringing || _current != null) {
        _current = null;
        if (!_calls.isClosed) _calls.add(null);
      }
    }
  }

  Future<void> _announce() async {
    _announced = true;
    _hintTimer?.cancel();
    final hint = _hint;
    ContactMatch? match;
    if (hint != null && hint.trim().isNotEmpty && !looksLikePhoneNumber(hint)) {
      try {
        match = await _match(hint);
      } catch (_) {
        match = null;
      }
    }
    if (_state != PhoneCallState.ringing) return;
    _current = identifyCaller(hint, match);
    if (!_calls.isClosed) _calls.add(_current);
  }

  @override
  Future<bool> answer() => _invokeBool('answer');

  @override
  Future<bool> reject() => _invokeBool('reject');

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (e) {
      debugPrint('[Calls] $method başarısız: ${e.runtimeType}');
      return false;
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    if (_handlerSet) _channel.setMethodCallHandler(null);
    _calls.close();
    _states.close();
  }
}
