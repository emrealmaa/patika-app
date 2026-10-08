import Flutter

/// Uygulamanın paket kimliği (kanal `patika/identity`), `AppIdentity.kt`'nin
/// iOS karşılığı.
///
/// Neden: Google Cloud'da Routes/Places anahtarı "iOS uygulaması"
/// kısıtlamasıyla sınırlandığında REST çağrısı `X-Ios-Bundle-Identifier`
/// başlığını KENDİSİ göndermelidir; yoksa istek 403 alır. iOS kısıtlamasında
/// imza parmak izi yok, yalnızca paket kimliği. `platform` alanı Dart'ın
/// hangi başlıkları göndereceğini seçer (bkz. `appRestrictionHeaders`).
enum AppIdentity {
  private static let channel = "patika/identity"

  static func attach(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "get":
          result(["package": Bundle.main.bundleIdentifier, "platform": "ios"])
        default: result(FlutterMethodNotImplemented)
        }
      }
  }
}
