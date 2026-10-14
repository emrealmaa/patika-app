import 'dart:async';

import '../ble/glasses_protocol.dart';
import 'glasses_wifi_service.dart';

/// Gözlük SoftAP bağlantısının simülasyonu (Test Modu). Gerçek ağ isteği yok;
/// sonraki denemenin sonucu ([declineNext], [unavailableNext]) ve bağlıyken
/// kopma/geri gelme ([drop], [restore]) elle seçilir.
class SimulatedGlassesWifiService implements GlassesWifiService {
  /// Onay penceresinin "açılıp" kapanması kadar gecikme.
  final Duration approvalDelay;

  SimulatedGlassesWifiService({
    this.approvalDelay = const Duration(milliseconds: 600),
    this.supportResult = const GlassesWifiSupport(supported: true, needsNearbyPermission: false),
  });

  final GlassesWifiSupport supportResult;
  final _controller = StreamController<GlassesWifiStatus>.broadcast();
  GlassesWifiStatus _status = GlassesWifiStatus.idle;
  Timer? _pending;

  /// Sonraki [connect] onay penceresinde reddedilsin.
  bool declineNext = false;

  /// Sonraki [connect] hiç denenemesin (ör. Wi-Fi kapalı).
  GlassesWifiUnavailableReason? unavailableNext;

  /// Son bağlanma isteğinin ağ bilgisi (testler için).
  GlassesWifiCredentials? lastCredentials;
  int connectCalls = 0;

  @override
  Stream<GlassesWifiStatus> get statuses => _controller.stream;

  @override
  GlassesWifiStatus get status => _status;

  @override
  Future<GlassesWifiSupport> support() async => supportResult;

  @override
  Future<void> connect(GlassesWifiCredentials credentials) async {
    connectCalls++;
    lastCredentials = credentials;
    _pending?.cancel();
    final unavailable = unavailableNext;
    unavailableNext = null;
    if (unavailable != null) {
      _set(GlassesWifiStatus(GlassesWifiState.unavailable, unavailable));
      return;
    }
    _set(const GlassesWifiStatus(GlassesWifiState.requesting));
    final decline = declineNext;
    declineNext = false;
    _pending = Timer(approvalDelay, () {
      _pending = null;
      _set(GlassesWifiStatus(
          decline ? GlassesWifiState.userDeclined : GlassesWifiState.connected));
    });
  }

  /// Bağlıyken ağın kopması (gözlük kapandı, menzil dışı).
  void drop() {
    if (_status.state == GlassesWifiState.connected) {
      _set(const GlassesWifiStatus(GlassesWifiState.lost));
    }
  }

  /// Kopan ağın geri gelmesi (istek açık kaldığı için onaysız).
  void restore() {
    if (_status.state == GlassesWifiState.lost) {
      _set(const GlassesWifiStatus(GlassesWifiState.connected));
    }
  }

  @override
  Future<void> disconnect() async {
    _pending?.cancel();
    _pending = null;
    _set(GlassesWifiStatus.idle);
  }

  void _set(GlassesWifiStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  void dispose() {
    _pending?.cancel();
    _controller.close();
  }
}
