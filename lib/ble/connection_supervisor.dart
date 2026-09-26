import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ble_connection_state.dart';
import 'device_memory.dart';
import 'glasses_protocol.dart';
import 'patika_ble_service.dart';

/// Gözlük bağlantısının sağlığından sorumlu tek sınıf: açılışta otomatik
/// bağlanma, heartbeat izleme ve üstel geri çekilmeli yeniden bağlanma.
/// Servislerin ([PatikaBleService]) ÜSTÜNDE durduğu için gerçek ve
/// simülasyon aynı mantığı kullanıyor.
///
/// "Bağlı" ile "sağlıklı" ayrı: BLE bağlantısı kurulmuş ama daha önce
/// heartbeat göndermiş bir gözlükten henüz heartbeat gelmemişse bağlantı
/// sağlıklı sayılmıyor. Böylece donmuş bir gözlük "bağlandı/koptu"
/// duyurularıyla sonsuz döngüye girmiyor - bu durum başarısız deneme
/// sayılıyor ve [failureNoticeAfter] denemeden sonra kullanıcıya bir kez
/// haber veriliyor.
class ConnectionSupervisor {
  static const backoffBase = Duration(seconds: 1);
  static const backoffMax = Duration(seconds: 30);
  static const failureNoticeAfter = 3;

  final PatikaBleService _service;
  final DeviceMemory _memory;
  final double Function() _jitter;

  /// Bağlantı sağlıklı hale geldi ("Gözlük bağlandı").
  final void Function() onHealthy;

  /// Sağlıklı bağlantı koptu ("Gözlük bağlantısı koptu").
  final void Function() onLost;

  /// Art arda [failureNoticeAfter] deneme başarısız oldu (kesinti başına
  /// bir kez).
  final void Function() onPersistentFailure;

  final List<StreamSubscription> _subs = [];
  final Set<String> _heartbeatCapable = {};

  BleConnectionState _state = BleConnectionState.disconnected;
  String? _targetId;
  bool _autoReconnect = false;
  bool _autoConnectFromScan = false;
  bool _healthy = false;
  bool _noticeGiven = false;
  bool _disposed = false;
  int _failedAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _watchdog;

  ConnectionSupervisor(
    this._service,
    this._memory, {
    required this.onHealthy,
    required this.onLost,
    required this.onPersistentFailure,
    double Function()? jitter,
  }) : _jitter = jitter ?? _randomJitter {
    _subs
      ..add(_service.connectionState.listen(_onState))
      ..add(_service.heartbeats.listen((_) => _onHeartbeat()))
      ..add(_service.discoveredDevices.listen(_onDevices));
  }

  static final _random = Random();

  /// ±%20 - aynı anda kopan birçok cihaz aynı saniyede denemesin.
  static double _randomJitter() => _random.nextDouble() * 0.4 - 0.2;

  /// [attempt]. yeniden deneme öncesi bekleme: 1, 2, 4, 8, 16, 30, 30... sn.
  static Duration backoffDelay(int attempt, {double jitter = 0}) {
    final ms = backoffBase.inMilliseconds * pow(2, max(0, attempt - 1));
    final capped = min(ms, backoffMax.inMilliseconds);
    return Duration(milliseconds: (capped * (1 + jitter)).round());
  }

  bool get isHealthy => _healthy;
  bool get isReconnecting => _reconnectTimer != null;
  int get failedAttempts => _failedAttempts;

  /// Açılışta: son cihaz biliniyorsa doğrudan ona bağlanır; değilse tarar
  /// ve tek bir Patika gözlüğü bulunursa ona bağlanır (birden fazlaysa
  /// seçimi kullanıcıya bırakır).
  Future<void> start() async {
    final lastId = await _memory.read();
    if (_disposed) return;
    if (lastId != null) {
      connect(lastId);
    } else {
      _autoConnectFromScan = true;
      _service.startScan();
    }
  }

  /// Kullanıcı (ya da otomatik tarama) bir cihaz seçti.
  void connect(String deviceId) {
    _autoConnectFromScan = false;
    _targetId = deviceId;
    _autoReconnect = true;
    _failedAttempts = 0;
    _noticeGiven = false;
    _cancelReconnect();
    _service.connect(deviceId);
  }

  /// Kullanıcı bilerek kesti - yeniden bağlanma denenmez ve [onLost]
  /// çağrılmaz (bu bir kopma değil; duyuruyu çağıran yapar).
  void disconnect() {
    _autoReconnect = false;
    _autoConnectFromScan = false;
    _healthy = false;
    _cancelReconnect();
    _watchdog?.cancel();
    _service.disconnect();
  }

  void _onState(BleConnectionState state) {
    final previous = _state;
    _state = state;

    switch (state) {
      case BleConnectionState.connected:
        _cancelReconnect();
        final id = _targetId;
        if (id != null && _heartbeatCapable.contains(id)) {
          // Heartbeat bekleniyor; gelmezse bu bağlantı da sayılmaz.
          _armWatchdog();
        } else {
          _markHealthy();
        }
      case BleConnectionState.disconnected:
        _watchdog?.cancel();
        if (previous == BleConnectionState.scanning) {
          _autoConnectFromScan = false;
          return;
        }
        if (previous != BleConnectionState.connected &&
            previous != BleConnectionState.connecting) {
          return;
        }
        final wasHealthy = _healthy;
        _healthy = false;
        if (wasHealthy) onLost();
        if (!_autoReconnect || _targetId == null || _reconnectTimer != null) return;

        if (wasHealthy) {
          _failedAttempts = 0;
          _scheduleReconnect(1);
        } else {
          _failedAttempts++;
          if (_failedAttempts >= failureNoticeAfter && !_noticeGiven) {
            _noticeGiven = true;
            onPersistentFailure();
          }
          _scheduleReconnect(_failedAttempts + 1);
        }
      case BleConnectionState.scanning:
      case BleConnectionState.connecting:
        break;
    }
  }

  void _onHeartbeat() {
    if (_state != BleConnectionState.connected) return;
    final id = _targetId;
    if (id != null) _heartbeatCapable.add(id);
    _armWatchdog();
    if (!_healthy) _markHealthy();
  }

  void _markHealthy() {
    _healthy = true;
    _failedAttempts = 0;
    _noticeGiven = false;
    final id = _targetId;
    if (id != null) _memory.write(id);
    onHealthy();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(GlassesProtocol.heartbeatTimeout, () {
      _watchdog = null;
      if (_state != BleConnectionState.connected) return;
      debugPrint('[Supervisor] heartbeat zaman aşımı, bağlantı kopmuş sayılıyor');
      // Servis disconnected yayınlayınca _onState yeniden bağlanmayı kurar.
      _service.disconnect();
    });
  }

  void _onDevices(List<DiscoveredDevice> devices) {
    if (!_autoConnectFromScan || devices.length != 1) return;
    connect(devices.single.id);
  }

  void _scheduleReconnect(int attempt) {
    final delay = backoffDelay(attempt, jitter: _jitter());
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      final id = _targetId;
      if (_disposed || !_autoReconnect || id == null) return;
      _service.connect(id);
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelReconnect();
    _watchdog?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
  }
}
