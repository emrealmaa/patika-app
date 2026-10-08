import Flutter

/// Acil kişi listesini (Faz 7) saklar (kanal `patika/emergency_contacts`),
/// `EmergencyContactsStorage.kt`'nin iOS karşılığı.
///
/// Android'deki `noBackupFilesDir`in karşılığı: dosya Application Support
/// altında ve `isExcludedFromBackup` işaretli, yani iCloud yedeğine ve
/// bilgisayar yedeğine girmez. Uygulamanın diğer verileri (ayarlar, takma
/// adlar) olağan yedeklenmeye devam ediyor; yalnızca bu liste istisna.
///
/// Dosya koruması `completeUntilFirstUserAuthentication`: SOS ekran
/// kilitliyken (telefon cepteyken) tetiklenir, `complete` korumasında dosya
/// kilitliyken okunamazdı. Cihaz açıldıktan sonra ilk kilit açılışına kadar
/// şifreli kalır.
///
/// Dosya küçük olduğu için tek parça JSON metni; ayrıştırma Dart tarafında.
enum EmergencyContactsStorage {
  private static let channel = "patika/emergency_contacts"
  private static let fileName = "emergency_contacts.json"

  static func attach(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "read":
          result(read())
        case "write":
          let json = (call.arguments as? [String: Any])?["json"] as? String ?? "[]"
          do {
            try write(json)
            result(nil)
          } catch {
            NSLog("[PatikaEmergencyContacts] Yazılamadı: \(error)")
            result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func fileURL() throws -> URL {
    let dir = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return dir.appendingPathComponent(fileName)
  }

  private static func read() -> String? {
    do {
      let url = try fileURL()
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      NSLog("[PatikaEmergencyContacts] Okunamadı: \(error)")
      return nil
    }
  }

  private static func write(_ json: String) throws {
    var url = try fileURL()
    try Data(json.utf8).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    // Atomik yazım dosyayı yeniden oluşturur: işaret her yazımda yeniden konur.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}
