import 'dart:async';

import 'package:flutter/foundation.dart';

import '../accessibility/announcement_queue.dart';
import '../accessibility/feedback_hub.dart';
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

  /// SOS araması gibi konuşulmaması gereken anlar: duyuru bekletilir,
  /// [flushHeld] ile sonra söylenir (bkz. SOS "arama sırasında konuşma yok").
  final bool Function() _holdSpeech;

  /// Konuşmanın (onay penceresi öncesi yönlendirme) en fazla bekleneceği süre.
  static const speechTimeout = Duration(seconds: 12);

  GlassesWifiService _service;
  StreamSubscription<GlassesWifiStatus>? _sub;

  /// Ekran (Test Modu) için son durum.
  final status = ValueNotifier<GlassesWifiStatus>(GlassesWifiStatus.idle);

  /// Gözlüğün son gönderdiği ağ bilgisi (parola içerir, günlüğe yazılmaz).
  GlassesWifiCredentials? credentials;

  /// Bu oturumda bir kez bağlanıldıysa onay penceresi yönlendirmesi tekrar
  /// söylenmez (her bağlanmada aynı uzun cümle spam olurdu).
  bool _connectedOnce = false;

  /// Kullanıcı kapattığında "idle" duyurulur; native'in kendi "idle"ı değil.
  bool _closing = false;

  _Held? _held;

  GlassesWifiController({
    required FeedbackHub feedback,
    required GlassesWifiService service,
    required Future<bool> Function() ensurePermission,
    bool Function()? holdSpeech,
  })  : _feedback = feedback,
        _service = service,
        _ensurePermission = ensurePermission,
        _holdSpeech = holdSpeech ?? _never {
    _listen();
  }

  static bool _never() => false;

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
      debugPrint('[GlassesWifi] Android 10+ gerekiyor, özellik kapalı');
      _setStatus(const GlassesWifiStatus(
          GlassesWifiState.unavailable, GlassesWifiUnavailableReason.unsupported));
      _speak(Tr.glassesCameraUnsupported);
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

  /// Bağlantıyı bilerek kapatır ("kapatıldı" denir).
  Future<void> disconnect() async {
    if (status.value.state == GlassesWifiState.idle) return;
    _closing = true;
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

  void _speak(String text) => _signalOrHold(null, text, AnnouncementPriority.normal);

  void _signal(FeedbackEvent event, String text,
          {AnnouncementPriority priority = AnnouncementPriority.normal}) =>
      _signalOrHold(event, text, priority);

  void _signalOrHold(FeedbackEvent? event, String text, AnnouncementPriority priority) {
    if (_holdSpeech()) {
      // Yalnızca en son durum anlamlı: eski bekleyen atılır.
      _held = _Held(event, text, priority);
      return;
    }
    // Kuyruğun 3 sn birleştirmesi kapalı: durum tekrarları zaten [_onStatus]'ta
    // eleniyor. Açık olsaydı hızlı "koptu -> bağlandı" dönüşünde ikinci
    // "bağlandı" yutulur, kullanıcının duyduğu son şey "koptu" kalırdı.
    if (event != null) _feedback.signal(event);
    _feedback.say(text, priority: priority, dedupe: false);
  }

  /// Konuşma yasağı bitince bekleyen son duyuruyu söyler.
  void flushHeld() {
    final held = _held;
    if (held == null || _holdSpeech()) return;
    _held = null;
    _signalOrHold(held.event, held.text, held.priority);
  }

  void dispose() {
    _sub?.cancel();
    status.dispose();
  }
}

class _Held {
  final FeedbackEvent? event;
  final String text;
  final AnnouncementPriority priority;

  const _Held(this.event, this.text, this.priority);
}
