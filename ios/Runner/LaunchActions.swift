import AppIntents
import Flutter

/// Uygulamanın dışından gelen başlatma talimatları (kanal `patika/launch`),
/// Android'deki Hızlı Ayarlar karosunun (`ListenTileService.kt`,
/// `MainActivity.handleLaunchIntent`) iOS karşılığı.
///
/// Talimat burada bekletilir: Dart açılışta `consumePendingAction` ile kendisi
/// sorar, zaten çalışıyorsa `actionPending` bildirimiyle haberdar olur. Böylece
/// soğuk açılışta da (Dart henüz hazır değilken), uygulama açıkken de
/// kaybolmaz (bkz. `lib/platform/launch_actions.dart`).
enum LaunchActions {
  private static let channelName = "patika/launch"
  private static var channel: FlutterMethodChannel?
  private static var pendingAction: String?

  static func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "consumePendingAction":
        result(pendingAction)
        pendingAction = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  static func request(_ action: String) {
    pendingAction = action
    channel?.invokeMethod("actionPending", arguments: nil)
  }
}

/// "Dinlemeyi başlat": uygulamayı açar ve sesli komut dinlemeye başlar.
/// Tek intent; Siri, Eylem Düğmesi (iPhone 15 Pro ve sonrası), Kestirmeler ve
/// Spotlight'ın hepsi bunu kullanır. Denetim Merkezi düğmesi (iOS 18
/// `ControlWidget`) ayrı bir widget uzantısı hedefi gerektirir, henüz yok.
@available(iOS 16.0, *)
struct ListenIntent: AppIntent {
  static var title: LocalizedStringResource = "Dinlemeyi başlat"
  static var description = IntentDescription("Patika'yı açar ve sesli komut dinlemeye başlar.")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    LaunchActions.request("listen")
    return .result()
  }
}

/// Kurulumsuz kestirme: kullanıcı Kestirmeler'de bir şey oluşturmadan Siri'ye
/// söyleyebilir ve Eylem Düğmesi'ne atayabilir. Türkçe Siri'nin cümleyi
/// tanıması cihazda doğrulanmadı.
@available(iOS 16.0, *)
struct PatikaShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ListenIntent(),
      phrases: [
        "\(.applicationName) dinle",
        "\(.applicationName) ile konuş",
      ]
    )
  }
}
