import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../navigation/geo.dart';
import '../navigation/guidance_engine.dart' show PositionFix;

/// Konum kaynağının söylemesi gereken sorunlar.
enum LocationIssue {
  /// Telefonun konum servisi kapalı.
  serviceDisabled,

  /// Konum izni yok ya da geri alındı.
  permissionDenied,
}

/// Telefonun konumu (Faz 6). `PatikaBleService`/`PatikaCallService` gibi
/// gerçek ve simülasyon uygulamaları birbirinin yerine geçer; navigasyon
/// (`NavigationSession`) hangisinin çalıştığını bilmez.
abstract class PatikaLocationService {
  /// Konum okumaları ([start] ile [stop] arasında akar).
  Stream<PositionFix> get fixes;

  /// Kaynak bir sorun bildirirse ("konum kapalı", "izin yok").
  Stream<LocationIssue> get issues;

  /// Telefonun konum servisi (GPS anahtarı) açık mı?
  Future<bool> isServiceEnabled();

  Future<void> start();
  Future<void> stop();

  /// Tek seferlik konum (rota başlangıcı için); alınamazsa null.
  Future<PositionFix?> currentPosition();

  void dispose();
}

/// Test Modu ve testler için: konumu elle (ya da bir yürüyüş betiğiyle)
/// veren sahte kaynak.
class SimulatedLocationService implements PatikaLocationService {
  final DateTime Function() _now;
  final _fixes = StreamController<PositionFix>.broadcast();
  final _issues = StreamController<LocationIssue>.broadcast();

  PositionFix? _last;
  bool _running = false;
  bool serviceEnabled = true;

  SimulatedLocationService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  bool get isRunning => _running;
  PositionFix? get lastFix => _last;

  @override
  Stream<PositionFix> get fixes => _fixes.stream;

  @override
  Stream<LocationIssue> get issues => _issues.stream;

  /// Yeni bir okuma yayınlar. [start] çağrılmadıysa (navigasyon yokken) yok sayılır
  /// ama son konum yine de hatırlanır.
  void emit(LatLng position, {double accuracy = 5, DateTime? time}) {
    final fix = PositionFix(position, accuracy, time ?? _now());
    _last = fix;
    if (_running) _fixes.add(fix);
  }

  void reportIssue(LocationIssue issue) => _issues.add(issue);

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<void> start() async => _running = true;

  @override
  Future<void> stop() async => _running = false;

  @override
  Future<PositionFix?> currentPosition() async => _last;

  @override
  void dispose() {
    _fixes.close();
    _issues.close();
  }
}

/// Gerçek konum: `geolocator`. Android'de Google Play Hizmetleri (Fused)
/// yoksa eklenti kendiliğinden Android `LocationManager`'a düşer. Play
/// Hizmetleri var ama konum vermiyorsa (bozuk/güncellenmemiş) [noFixTimeout]
/// sonra `forceLocationManager` ile bir kez yeniden denenir.
class GeolocatorLocationService implements PatikaLocationService {
  final Duration noFixTimeout;

  final _fixes = StreamController<PositionFix>.broadcast();
  final _issues = StreamController<LocationIssue>.broadcast();

  StreamSubscription<geo.Position>? _sub;
  Timer? _fallbackTimer;
  bool _forceLocationManager = false;
  bool _gotFix = false;

  GeolocatorLocationService({this.noFixTimeout = const Duration(seconds: 20)});

  @override
  Stream<PositionFix> get fixes => _fixes.stream;

  @override
  Stream<LocationIssue> get issues => _issues.stream;

  @override
  Future<bool> isServiceEnabled() async {
    try {
      return await geo.Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('[Location] servis durumu okunamadı: $e');
      return false;
    }
  }

  @override
  Future<void> start() async {
    if (_sub != null) return;
    _gotFix = false;
    _forceLocationManager = false;
    _listen();
  }

  void _listen() {
    _sub = geo.Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _onPosition,
      onError: _onError,
    );
    _fallbackTimer?.cancel();
    if (!_forceLocationManager) {
      _fallbackTimer = Timer(noFixTimeout, _retryWithLocationManager);
    }
  }

  geo.LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: _forceLocationManager,
      );
    }
    return const geo.LocationSettings(accuracy: geo.LocationAccuracy.best, distanceFilter: 0);
  }

  void _onPosition(geo.Position p) {
    _gotFix = true;
    _fallbackTimer?.cancel();
    _fixes.add(_toFix(p));
  }

  void _onError(Object error) {
    if (error is geo.LocationServiceDisabledException) {
      _issues.add(LocationIssue.serviceDisabled);
    } else if (error is geo.PermissionDeniedException) {
      _issues.add(LocationIssue.permissionDenied);
    } else {
      debugPrint('[Location] hata: $error');
    }
  }

  Future<void> _retryWithLocationManager() async {
    if (_gotFix || _sub == null || _forceLocationManager) return;
    debugPrint('[Location] $noFixTimeout içinde konum gelmedi; LocationManager ile yeniden deneniyor');
    _forceLocationManager = true;
    await _sub?.cancel();
    _listen();
  }

  @override
  Future<void> stop() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<PositionFix?> currentPosition() async {
    try {
      final p = await geo.Geolocator.getCurrentPosition(
        locationSettings: geo.LocationSettings(
          accuracy: geo.LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        ),
      );
      return _toFix(p);
    } catch (e) {
      debugPrint('[Location] anlık konum alınamadı: $e');
      return null;
    }
  }

  static PositionFix _toFix(geo.Position p) =>
      PositionFix(LatLng(p.latitude, p.longitude), p.accuracy, p.timestamp);

  @override
  void dispose() {
    stop();
    _fixes.close();
    _issues.close();
  }
}
