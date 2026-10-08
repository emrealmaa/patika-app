import Flutter
import UIKit

/// Telefonun pil yüzdesini ve şarj durumunu verir (kanal `patika/battery`),
/// `BatteryProbe.kt`'nin iOS karşılığı.
///
/// `UIDevice` pil izlemesi açılınca son değeri hemen verir, izin gerekmez.
/// Dart tarafı 30 sn'de bir yoklar (bkz. `AppState.pollPhoneBattery`); olay
/// bildirimi (`batteryLevelDidChangeNotification`) bu yüzden kullanılmıyor.
///
/// Okunamazsa (simülatörde düzey hep -1, durum `.unknown`) `nil` döner; Dart
/// tarafı bunu "bilinmiyor" sayar ve uydurma bir değer söylemez.
enum BatteryProbe {
  private static let channel = "patika/battery"

  static func attach(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "read": result(read())
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func read() -> [String: Any]? {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let level = device.batteryLevel
    if level < 0 || device.batteryState == .unknown { return nil }
    let charging = device.batteryState == .charging || device.batteryState == .full
    return ["level": Int((level * 100).rounded()), "charging": charging]
  }
}
