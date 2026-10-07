import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Uygulamanın kendi kanalları (Android'de MainActivity.configureFlutterEngine).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PatikaChannels") {
      let messenger = registrar.messenger()
      AppIdentity.attach(messenger: messenger)
      BatteryProbe.attach(messenger: messenger)
      EmergencyContactsStorage.attach(messenger: messenger)
    }
  }
}
