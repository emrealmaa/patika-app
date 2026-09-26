import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/strings_tr.dart';

/// Uygulama arka plandayken ve ekran kilitliyken süreci canlı tutan
/// Android foreground service (kalıcı bildirim "Patika gözlüğe bağlı").
///
/// Servisin kendisi iş yapmıyor: BLE, komut işleme ve duyurular ana
/// isolate'te (AppState) kalıyor - servis sadece Android'in süreci
/// öldürmesini engelliyor. Böylece mevcut soyutlamalar isolate'ler arası
/// mesajlaşmaya bölünmüyor.
///
/// Manifest'teki `android:stopWithTask="true"`: kullanıcı uygulamayı son
/// uygulamalardan kaydırırsa servis de kapanır. Aksi halde ana isolate
/// ölmüşken bildirim "bağlı" demeye devam ederdi (yanıltıcı).
class BackgroundService {
  static const _serviceId = 4210;

  bool _initialized = false;
  bool _running = false;
  String? _lastText;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'patika_connection',
        channelName: Tr.notificationChannel,
        channelDescription: Tr.notificationChannelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      // stopWithTask burada BİLEREK verilmiyor: bu eklentide (10.0.0)
      // Dart tarafındaki stopWithTask: true, uygulama görünmez olur olmaz
      // (ana ekrana dönünce/ekran kilitlenince) servisi durduruyor -
      // emülatörde doğrulandı. "Son uygulamalardan kaydırınca dur"
      // davranışı AndroidManifest'teki android:stopWithTask="true" ile
      // sağlanıyor.
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    _initialized = true;
  }

  /// Servisi başlatır. Android 14+ kuralı: mikrofon türü ancak mikrofon izni
  /// ZATEN verilmişse eklenebilir (yoksa servis hiç başlamaz). İzin sonradan
  /// verilirse arka planda dinleme için servis Faz 2'de yeniden başlatılacak.
  Future<void> start(String text) async {
    try {
      _init();
      if (await FlutterForegroundTask.isRunningService) {
        _running = true;
        return update(text);
      }
      final micGranted = await Permission.microphone.isGranted;
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: [
          ForegroundServiceTypes.connectedDevice,
          if (micGranted) ForegroundServiceTypes.microphone,
        ],
        notificationTitle: Tr.notificationTitle,
        notificationText: text,
        callback: startCallback,
      );
      _running = result is ServiceRequestSuccess;
      _lastText = text;
      if (!_running) debugPrint('[Background] başlatılamadı: $result');
    } catch (e) {
      // Plugin yok (testler) ya da platform desteklemiyor.
      debugPrint('[Background] başlatılamadı: $e');
    }
  }

  /// Bildirim metnini günceller (aynı metin tekrar gönderilmez).
  Future<void> update(String text) async {
    if (!_running || text == _lastText) return;
    _lastText = text;
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (e) {
      debugPrint('[Background] güncellenemedi: $e');
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[Background] durdurulamadı: $e');
    }
  }
}

/// Servis kendi isolate'inde bunu çalıştırır; iş yapmayan bir handler
/// yeterli (bkz. sınıf açıklaması). Top-level ve entry-point olmak zorunda.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
