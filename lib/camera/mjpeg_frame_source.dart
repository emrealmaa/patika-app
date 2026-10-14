import 'dart:async';

import '../accessibility/announcement_queue.dart';
import '../accessibility/feedback_hub.dart';
import '../accessibility/held_announcer.dart';
import '../glasses_wifi/glasses_wifi_controller.dart';
import '../glasses_wifi/glasses_wifi_service.dart';
import '../l10n/strings_tr.dart';
import 'camera_config.dart';
import 'frame_source.dart';
import 'mjpeg_parser.dart';
import 'mjpeg_transport.dart';

/// Gözlük kamerası: `frm on` (BLE) -> gözlük ağ bilgisini gönderir ->
/// uygulamaya özel Wi-Fi (Madde 1) -> MJPEG akışı -> ayrıştırma -> kareler.
///
/// Ağ koparsa akış durur ([FrameSourceState.interrupted], kopmayı Wi-Fi
/// denetleyicisi söyler); ağ geri gelince akış kendiliğinden yeniden açılır.
/// Ağ açıkken kare gelmezse ([CameraConfig.stallTimeout]) bir kez "görüntü
/// gelmiyor" denir, kareler dönünce bir kez "geri geldi". Sessiz kopma yok,
/// tekrar eden duyuru yok.
///
/// Arka plan servisi: süreç canlı kaldıkça (ekran kilitli de) akış sürer;
/// servis yalnızca süreci tutar, akışın kendisi ana isolate'te. Pil/ısınma:
/// kare hızı ve çözünürlük [CameraConfig]'te; gözlük ısınma/pil bilgisi
/// protokolde yok (firmware'de netleşecek).
class MjpegFrameSource extends FrameSourceBase {
  final Future<bool> Function(bool on) _sendFrm;
  final GlassesWifiController _wifi;
  final MjpegTransport Function() _transport;
  final HeldAnnouncer _announcer;

  MjpegFrameSource({
    required super.config,
    required Future<bool> Function(bool on) sendFrm,
    required GlassesWifiController wifi,
    required MjpegTransport Function() transport,
    required FeedbackHub feedback,
    bool Function()? holdSpeech,
    super.now,
  })  : _sendFrm = sendFrm,
        _wifi = wifi,
        _transport = transport,
        _announcer = HeldAnnouncer(feedback, hold: holdSpeech);

  bool _wanted = false;
  bool _frmSent = false;
  bool _stallAnnounced = false;
  StreamSubscription<MjpegEvent>? _stream;
  MjpegParser? _parser;
  Timer? _stallTimer;
  Timer? _credentialsTimer;
  Timer? _reopenTimer;

  /// Ayrıştırıcının attığı bozuk kareler (tüm oturumlar).
  int parseErrors = 0;

  bool get _networkUp => _wifi.status.value.state == GlassesWifiState.connected;

  @override
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    resetCounters();
    parseErrors = 0;
    setState(FrameSourceState.starting);
    _say(Tr.cameraStarting);
    final sent = await _sendFrm(true);
    if (!_wanted) return;
    if (!sent) {
      _fail(Tr.cameraNoGlasses);
      return;
    }
    _frmSent = true;
    _wifi.status.addListener(_onWifi);
    _wifi.credentialsNotifier.addListener(_onCredentials);
    if (_networkUp) {
      _open();
    } else if (_wifi.credentials != null) {
      unawaited(_wifi.connect());
    } else {
      _credentialsTimer = Timer(config.credentialsTimeout, () {
        if (_wanted && _wifi.credentials == null) _fail(Tr.cameraNoCredentials);
      });
    }
  }

  void _onCredentials() {
    if (!_wanted || _wifi.credentials == null) return;
    _credentialsTimer?.cancel();
    final s = _wifi.status.value.state;
    if (s != GlassesWifiState.connected && s != GlassesWifiState.requesting) {
      unawaited(_wifi.connect());
    }
  }

  void _onWifi() {
    if (!_wanted) return;
    switch (_wifi.status.value.state) {
      case GlassesWifiState.connected:
        _open();
      case GlassesWifiState.lost:
        // Kopmayı Wi-Fi denetleyicisi söyledi; burada ikinci kez denmez.
        _closeStream();
        _stallTimer?.cancel();
        setState(FrameSourceState.interrupted);
      case GlassesWifiState.userDeclined:
      case GlassesWifiState.unavailable:
        // Nedeni Wi-Fi denetleyicisi söyledi.
        _fail(null);
      case GlassesWifiState.idle:
        // Ağ başka yerden kapatıldı (Test Modu): akış da biter.
        _fail(null);
      case GlassesWifiState.requesting:
        break;
    }
  }

  void _open() {
    _reopenTimer?.cancel();
    _closeStream();
    _parser = null;
    _stream = _transport().open(config.streamUrl).listen(
          _onEvent,
          onError: (_) => _onClosed(),
          onDone: _onClosed,
        );
    _armStall();
  }

  void _onEvent(MjpegEvent event) {
    switch (event) {
      case MjpegHeader(:final contentType):
        _parser = MjpegParser(
          boundary: MjpegParser.boundaryFromContentType(contentType),
          maxFrameBytes: config.maxFrameBytes,
        );
      case MjpegChunk(:final bytes):
        final parser = _parser ??= MjpegParser(maxFrameBytes: config.maxFrameBytes);
        final before = parser.dropped;
        final jpegs = parser.add(bytes);
        parseErrors += parser.dropped - before;
        var any = false;
        for (final jpeg in jpegs) {
          any = emit(jpeg) || any;
        }
        if (jpegs.isNotEmpty) _onFrame(delivered: any);
    }
  }

  void _onFrame({required bool delivered}) {
    final s = state.value;
    if (s == FrameSourceState.starting) {
      _say(Tr.cameraStreaming);
    } else if (s == FrameSourceState.interrupted && _stallAnnounced) {
      _say(Tr.cameraResumed);
    }
    _stallAnnounced = false;
    if (s != FrameSourceState.streaming) setState(FrameSourceState.streaming);
    _armStall();
  }

  void _armStall() {
    _stallTimer?.cancel();
    _stallTimer = Timer(config.stallTimeout, () {
      if (!_wanted || !_networkUp) return;
      setState(FrameSourceState.interrupted);
      if (!_stallAnnounced) {
        _stallAnnounced = true;
        _say(Tr.cameraStalled, priority: AnnouncementPriority.high);
      }
    });
  }

  /// Ağ açıkken akış bağlantısı kapandı: kısa beklemeyle yeniden aç.
  void _onClosed() {
    _stream = null;
    if (!_wanted || !_networkUp) return;
    _reopenTimer?.cancel();
    _reopenTimer = Timer(config.reopenDelay, () {
      if (_wanted && _networkUp && _stream == null) _open();
    });
  }

  void _closeStream() {
    final s = _stream;
    _stream = null;
    s?.cancel();
  }

  void _cleanup() {
    _stallTimer?.cancel();
    _credentialsTimer?.cancel();
    _reopenTimer?.cancel();
    _closeStream();
    _wifi.status.removeListener(_onWifi);
    _wifi.credentialsNotifier.removeListener(_onCredentials);
    latest.clear();
  }

  void _fail(String? text) {
    _wanted = false;
    _cleanup();
    setState(FrameSourceState.failed);
    if (text != null) _say(text, event: FeedbackEvent.error);
    // Gözlük boşuna SoftAP/kamera açık tutmasın (pil).
    if (_frmSent) unawaited(_sendFrm(false));
    _frmSent = false;
  }

  @override
  Future<void> stop() async {
    final s = state.value;
    if (s == FrameSourceState.stopped || s == FrameSourceState.failed) {
      // Zaten durmuş/başarısız (nedeni söylendi): sessizce "durdu".
      setState(FrameSourceState.stopped);
      return;
    }
    _wanted = false;
    _cleanup();
    if (_frmSent) await _sendFrm(false);
    _frmSent = false;
    await _wifi.disconnect(announce: false);
    setState(FrameSourceState.stopped);
    _say(Tr.cameraStopped);
  }

  void _say(String text,
          {FeedbackEvent? event, AnnouncementPriority priority = AnnouncementPriority.normal}) =>
      _announcer.announce(text, event: event, priority: priority);

  /// SOS araması bitince bekleyen duyuru.
  void flushHeld() => _announcer.flush();

  @override
  void dispose() {
    _wanted = false;
    _cleanup();
    super.dispose();
  }
}
