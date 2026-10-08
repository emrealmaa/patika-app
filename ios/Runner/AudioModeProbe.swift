import CallKit
import Flutter

/// Arama sürüyor mu (kanal `patika/audiomode`), `AudioModeProbe.kt`'nin iOS
/// karşılığı. SOS, kendi başlattığı arama sürerken konuşmasın diye aramanın
/// bitişini bununla izler (bkz. `AudioModeCallMonitor`).
///
/// iOS'ta `AudioManager.getMode()` yok; `CXCallObserver` sistemdeki telefon
/// ve VoIP aramalarını izin istemeden verir. Dart sözleşmesi aynı kalsın diye
/// Android'in değerleri döndürülür: bitmemiş bir arama varsa 2
/// (`MODE_IN_CALL`), yoksa 0 (`MODE_NORMAL`). Android'den farkı: giden arama
/// karşı taraf açmadan (çalarken) de "sürüyor" görünür.
enum AudioModeProbe {
  private static let channel = "patika/audiomode"
  private static let modeNormal = 0
  private static let modeInCall = 2

  /// Gözlemci yaşadığı sürece `calls` güncel kalır: tek örnek tutulur.
  private static let observer = CXCallObserver()

  static func attach(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "mode":
          let inCall = observer.calls.contains { !$0.hasEnded }
          result(inCall ? modeInCall : modeNormal)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
