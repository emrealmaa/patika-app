import 'dart:async';

import 'package:flutter/foundation.dart';

import '../accessibility/announcement_queue.dart';
import '../accessibility/feedback_hub.dart';
import '../accessibility/held_announcer.dart';
import '../ble/glasses_protocol.dart';
import '../l10n/strings_tr.dart';
import 'glasses_wifi_service.dart';

/// Gözlük kamerası Wi-Fi bağlantısının akışı ve sesli bildirimleri:
/// ağ bilgisi (BLE `wifi` mesajı) -> destek/izin -> sesli yönlendirme ->
/// sistem onay penceresi -> sonuç. Her sonuç söylenir, kopma asla sessiz
/// geçmez; aynı durum iki kez gelirse ikinci kez söylenmez.
///
/// Bağlantı yalnızca açıkça istenince ([connect]) kurulur: ağ bilgisi gelince
/// kendiliğinden bağlanmaz, çünkü sistem onay penceresi beklenmedik anda
/// açılmamalı (Madde 2'de kamera akışı başlatılırken istenecek).
class GlassesWifiController {
  final FeedbackHub _feedback;

  /// Yakındaki Wi-Fi cihazları izni (Android 13+), sesli açıklamayla
  /// (`PermissionExplainer`). Yalnızca cihaz gerektiriyorsa çağrılır.
  final Future<bool> Function() _ensurePermission;

  /// SOS araması gibi konuşulmaması gereken anlarda duyuru bekletilir,
  /// [flushHeld] ile sonra söylenir (bkz. SOS "arama sırasında konuşma yok").
  final HeldAnnouncer _announcer;

  /// Konuşmanın (onay penceresi öncesi yönlendirme) en fazla bekleneceği süre.
  static const speechTimeout = Duration(seconds: 12);

  GlassesWifiService _service;
  StreamSubscription<GlassesWifiStatus>? _sub;

  /// Ekran (Test Modu) için son durum.
  final status = ValueNotifier<GlassesWifiStatus>(GlassesWifiStatus.idle);

  /// Gözlüğün son gönderdiği ağ bilgisi (parola içerir, günlüğe yazılmaz).
  /// Kamera akışı `frm on` sonrası bunun gelmesini bekler.
  final credentialsNotifier = ValueNotifier<GlassesWifiCredentials?>(null);

  GlassesWifiCredentials? get credentials => credentialsNotifier.value;
  set credentials(GlassesWifiCredentials? value) => credentialsNotifier.value = value;

  /// Bu oturumda bir kez bağlanıldıysa onay penceresi yönlendirmesi tekrar
  /// söylenmez (her bağlanmada aynı uzun cümle spam olurdu).
  bool _connectedOnce = false;

  /// Kullanıcı kapattığında "idle" duyurulur; native'in kendi "idle"ı değil.
  bool _closing = false;

  GlassesWifiController({
    required FeedbackHub feedback,
    required GlassesWifiService service,
    required Future<bool> Function() ensurePermission,
    bool Function()? holdSpeech,
  })  : _feedback = feedback,
        _service = service,
        _ensurePermission = ensurePermission,
        _announcer = HeldAnnouncer(feedback, hold: holdSpeech) {
    _listen();
  }

  GlassesWifiService get service => _service;

  /// Simülasyon <-> gerçek geçişi: eski servisi çağıran taraf kapatır.
  void useService(GlassesWifiService service) {
    _sub?.cancel();
    _service = service;
    _connectedOnce = false;
    _closing = false;
    _setStatus(service.status);
    _listen();
  }

  void _listen() {
    _sub = _service.statuses.listen(_onStatus);
  }

  /// Gözlükten yeni ağ bilgisi geldi.
  void updateCredentials(GlassesWifiCredentials value) => credentials = value;

  /// Gözlük ağına bağlanmayı dener. Sonuç sesle bildirilir.
  Future<void> connect() async {
    final creds = credentials;
    if (creds == null) {
      _speak(Tr.glassesCameraNoCredentials);
      return;
    }
    final support = await _service.support();
    if (!support.supported) {
      debugPrint('[GlassesWifi] desteklenmiyor (eski Android: ${support.oldAndroid})');
      _setStatus(const GlassesWifiStatus(
          GlassesWifiState.unavailable, GlassesWifiUnavailableReason.unsupported));
      _speak(support.oldAndroid ? Tr.glassesCameraUnsupported : Tr.glassesCameraUnsupportedPlatform);
      return;
    }
    if (support.needsNearbyPermission && !await _ensurePermission()) {
      _setStatus(const GlassesWifiStatus(
          GlassesWifiState.unavailable, GlassesWifiUnavailableReason.permission));
      _speak(Tr.glassesCameraPermissionDenied);
      return;
    }
    _closing = false;
    final text = _connectedOnce
        ? Tr.glassesCameraConnecting
        : '${Tr.glassesCameraConnecting}. ${Tr.glassesCameraApprovalHint}';
    // Onay penceresi konuşma bitince açılsın (TalkBack pencereyi okurken TTS
    // üstüne binmesin); TTS takılırsa sonsuza dek beklenmez.
    await _feedback.say(text).timeout(speechTimeout, onTimeout: () => false);
    await _service.connect(creds);
  }

  /// Bağlantıyı bilerek kapatır. [announce]: "kapatıldı" denir (kamera akışı
  /// kendi "kapatıldı"sını söylediğinde false: aynı şey iki kez söylenmez).
  Future<void> disconnect({bool announce = true}) async {
    if (status.value.state == GlassesWifiState.idle) return;
    _closing = announce;
    await _service.disconnect();
  }

  void _onStatus(GlassesWifiStatus next) {
    final previous = status.value;
    if (next == previous) return;
    _setStatus(next);
    switch (next.state) {
      case GlassesWifiState.requesting:
        break;
      case GlassesWifiState.connected:
        _connectedOnce = true;
        _signal(FeedbackEvent.connected, Tr.glassesCameraConnected);
      case GlassesWifiState.lost:
        // Sessiz kopma yasak: yüksek öncelik (gözlük BLE kopması gibi).
        _signal(FeedbackEvent.disconnected, Tr.glassesCameraLost,
            priority: AnnouncementPriority.high);
      case GlassesWifiState.userDeclined:
        _signal(FeedbackEvent.error, Tr.glassesCameraDeclined);
      case GlassesWifiState.unavailable:
        _signal(FeedbackEvent.error, unavailableText(next.reason));
      case GlassesWifiState.idle:
        if (_closing) _speak(Tr.glassesCameraClosed);
        _closing = false;
    }
  }

  static String unavailableText(GlassesWifiUnavailableReason? reason) => switch (reason) {
        GlassesWifiUnavailableReason.unsupported => Tr.glassesCameraUnsupported,
        GlassesWifiUnavailableReason.wifiOff => Tr.glassesCameraWifiOff,
        GlassesWifiUnavailableReason.permission => Tr.glassesCameraPermissionDenied,
        GlassesWifiUnavailableReason.error || null => Tr.glassesCameraError,
      };


  void _setStatus(GlassesWifiStatus value) => status.value = value;

  void _speak(String text) => _announcer.announce(text);

  void _signal(FeedbackEvent event, String text,
          {AnnouncementPriority priority = AnnouncementPriority.normal}) =>
      _announcer.announce(text, event: event, priority: priority);

  /// Konuşma yasağı bitince bekleyen son duyuruyu söyler.
  void flushHeld() => _announcer.flush();

  void dispose() {
    _sub?.cancel();
    status.dispose();
    credentialsNotifier.dispose();
  }
}
