import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ble/glasses_protocol.dart';

/// Gözlük SoftAP bağlantısının durumu (bkz. `GlassesNetwork.kt`).
enum GlassesWifiState {
  /// İstek yok (başlangıç ya da bilerek kapatıldı).
  idle,

  /// Ağ istendi; sistem onay penceresi gösteriyor olabilir.
  requesting,

  /// Ağ uygulamaya verildi. Varsayılan ağ (mobil veri) DEĞİŞMEDİ.
  connected,

  /// Bağlıyken koptu. İstek açık kalır: ağ geri gelirse yeniden [connected].
  lost,

  /// Bağlanma hiç denenemedi (bkz. [GlassesWifiUnavailableReason]).
  unavailable,

  /// Sistem onay penceresi kapandı: kullanıcı reddetti ya da pencere ağı
  /// bulamadı (Android ikisini ayırmıyor).
  userDeclined,
}

enum GlassesWifiUnavailableReason {
  /// Android 10'dan (API 29) eski: `WifiNetworkSpecifier` yok.
  unsupported,

  /// Telefonun Wi-Fi'ı kapalı.
  wifiOff,

  /// Yakındaki Wi-Fi cihazları izni verilmedi (Android 13+).
  permission,

  /// Geçersiz ağ bilgisi ya da platform hatası.
  error,
}

class GlassesWifiStatus {
  final GlassesWifiState state;
  final GlassesWifiUnavailableReason? reason;

  const GlassesWifiStatus(this.state, [this.reason]);

  static const idle = GlassesWifiStatus(GlassesWifiState.idle);

  @override
  bool operator ==(Object other) =>
      other is GlassesWifiStatus && other.state == state && other.reason == reason;

  @override
  int get hashCode => Object.hash(state, reason);

  @override
  String toString() => 'GlassesWifiStatus(${state.name}${reason == null ? '' : ', ${reason!.name}'})';
}

/// Cihazın bu özelliği destekleyip desteklemediği.
class GlassesWifiSupport {
  /// API 29+.
  final bool supported;

  /// Android 13+: NEARBY_WIFI_DEVICES çalışma zamanı izni gerekir.
  final bool needsNearbyPermission;

  const GlassesWifiSupport({required this.supported, required this.needsNearbyPermission});
}

/// Gözlüğün Wi-Fi SoftAP'ına uygulamaya özel bağlantı. Gerçek uygulama
/// ([MethodChannelGlassesWifiService]) Android'in `WifiNetworkSpecifier`
/// isteğini kullanır: sistemin varsayılan ağı değişmez, uygulamanın internet
/// istekleri (Google Routes/Places, Gemini) mobil veriden gitmeye devam eder.
/// Gözlüğe giden istekler (MJPEG, WebSocket) yalnızca native tarafta bu ağ
/// üzerinden yapılır. Simülasyon: [SimulatedGlassesWifiService].
abstract class GlassesWifiService {
  Stream<GlassesWifiStatus> get statuses;
  GlassesWifiStatus get status;

  Future<GlassesWifiSupport> support();

  /// Ağı ister. Sonuç [statuses] akışından gelir.
  Future<void> connect(GlassesWifiCredentials credentials);

  /// İsteği bırakır; durum [GlassesWifiState.idle] olur.
  Future<void> disconnect();

  void dispose();
}

class MethodChannelGlassesWifiService implements GlassesWifiService {
  /// Gözlük ağı kanalı. Yalnızca `lib/glasses_wifi/` kullanır; navigasyon ve
  /// Google istemcileri bu kanalı hiç görmez (testle kilitli).
  static const channelName = 'patika/glasses_wifi';
  static const _channel = MethodChannel(channelName);

  final _controller = StreamController<GlassesWifiStatus>.broadcast();
  GlassesWifiStatus _status = GlassesWifiStatus.idle;

  bool _handlerSet = false;

  /// Kanal dinleyicisi ilk kullanımda kurulur (durumlar yalnızca bir
  /// istekten sonra gelir; kurulum anında platform bağlamı gerekmesin).
  void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onState') return;
      final args = call.arguments;
      if (args is! Map) return;
      final next = parseNativeStatus(args['state'], args['reason']);
      if (next != null) _set(next);
    });
  }

  /// Native durum dizgisini çözer; tanınmayan değer null (yok sayılır).
  static GlassesWifiStatus? parseNativeStatus(Object? state, Object? reason) {
    GlassesWifiState? s;
    for (final v in GlassesWifiState.values) {
      if (v.name == state) s = v;
    }
    if (s == null) return null;
    GlassesWifiUnavailableReason? r;
    for (final v in GlassesWifiUnavailableReason.values) {
      if (v.name == reason) r = v;
    }
    if (s == GlassesWifiState.unavailable) r ??= GlassesWifiUnavailableReason.error;
    return GlassesWifiStatus(s, s == GlassesWifiState.unavailable ? r : null);
  }

  void _set(GlassesWifiStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Stream<GlassesWifiStatus> get statuses => _controller.stream;

  @override
  GlassesWifiStatus get status => _status;

  @override
  Future<GlassesWifiSupport> support() async {
    _ensureHandler();
    try {
      final map = await _channel.invokeMapMethod<String, bool>('support');
      return GlassesWifiSupport(
        supported: map?['supported'] ?? false,
        needsNearbyPermission: map?['nearbyPermission'] ?? false,
      );
    } catch (e) {
      debugPrint('[GlassesWifi] destek sorgulanamadı: $e');
      return const GlassesWifiSupport(supported: false, needsNearbyPermission: false);
    }
  }

  @override
  Future<void> connect(GlassesWifiCredentials credentials) async {
    _ensureHandler();
    try {
      await _channel.invokeMethod('connect', {
        'ssid': credentials.ssid,
        'passphrase': credentials.passphrase,
      });
    } catch (e) {
      // Ayrıntıda SSID/parola yok: yalnızca hata türü.
      debugPrint('[GlassesWifi] bağlanılamadı: ${e.runtimeType}');
      _set(const GlassesWifiStatus(
          GlassesWifiState.unavailable, GlassesWifiUnavailableReason.error));
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint('[GlassesWifi] kapatılamadı: ${e.runtimeType}');
      _set(GlassesWifiStatus.idle);
    }
  }

  @override
  void dispose() {
    if (_handlerSet) _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
