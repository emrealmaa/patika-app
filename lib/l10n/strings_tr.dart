/// Kullanıcıya giden (ekranda görünen ya da seslendirilen) tüm Türkçe
/// metinler tek yerde. Kurallar: kısa, doğal, teknik terim/kod yok -
/// görme engelli kullanıcı bunları kulaklıktan duyuyor, ekranda okumuyor.
abstract final class Tr {
  // --- Genel -------------------------------------------------------------
  static const appTitle = 'Patika Companion';
  static const tabConnection = 'Bağlantı';
  static const tabTestMode = 'Test Modu';
  static const tabSettings = 'Ayarlar';
  static const unexpectedError = 'Bir hata oluştu, komut tamamlanamadı';
  static const unknownCommand = 'Bu komutu anlayamadım';

  // --- Bağlantı ------------------------------------------------------------
  static const glassesConnected = 'Gözlük bağlandı';
  static const glassesDisconnected = 'Gözlük bağlantısı koptu';
  static const simulationMode = 'Simülasyon modu';
  static const simulationOn = 'Gözlük donanımı simüle ediliyor';
  static const simulationOff = 'Gerçek BLE ile taranıyor (donanım gerekir)';
  static const scan = 'Tara';
  static const disconnect = 'Bağlantıyı kes';
  static const foundDevices = 'Bulunan cihazlar';
  static const noDevices = 'Henüz cihaz bulunamadı.';
  static const recentCommands = 'Son komutlar';
  static const noCommands = 'Henüz işlenen bir komut yok.';
  static const connect = 'Bağlan';
  static String connectTo(String name) => '$name cihazına bağlan';
  static const stateDisconnected = 'Bağlı değil';
  static const stateScanning = 'Taranıyor…';
  static const stateConnecting = 'Bağlanıyor…';
  static const stateConnected = 'Bağlı';
  static String connectionStatus(String state) => 'Bağlantı durumu: $state';

  // --- Komut geçmişi -------------------------------------------------------
  static const success = 'Başarılı';
  static const failure = 'Başarısız';
  static String logEntryLabel(String title, bool ok, String message) =>
      '$title, ${ok ? "başarılı" : "başarısız"}: $message';
  static String logEntryTime(String time) => 'İşlem saati $time';
  static const commandHistory = 'İşlem geçmişi';

  // --- Komut sonuçları -----------------------------------------------------
  static const callNoTarget = 'Kimi arayacağımı anlayamadım';
  static const messageNoTarget = 'Kime mesaj göndereceğimi anlayamadım';
  static const navNoTarget = 'Nereye gitmek istediğinizi anlayamadım';
  static String contactNotFound(String name) => '$name rehberde bulunamadı';
  static const contactNotFoundDetail =
      'Rehber izni verilmemiş ya da isim farklı kaydedilmiş olabilir.';
  static String contactNoNumber(String name) => '$name için kayıtlı numara yok';
  static const dialerFailed = 'Arama uygulaması açılamadı';
  static String dialerOpened(String name) => '$name için arama ekranı açıldı';
  static const dialerOpenedDetail = 'Aramak için ekrandaki arama tuşuna basın.';
  static const smsFailed = 'Mesaj uygulaması açılamadı';
  static String smsOpened(String name) => '$name için mesaj ekranı açıldı';
  static const smsOpenedDetail = 'Mesajınızı yazıp gönder tuşuna basın.';
  static const mapsFailed = 'Harita uygulaması açılamadı';
  static String navStarted(String dest) => '$dest için yürüyüş yönlendirmesi başladı';
  static const navStartedDetail = 'Yönlendirme harita uygulamasında açıldı.';
  static String time(String hhmm) => 'Saat $hhmm';
  static const weatherNotReady = 'Hava durumu henüz hazır değil';
  static const newsNotReady = 'Haberler henüz hazır değil';
  static const musicNotReady = 'Müzik kontrolü henüz hazır değil';
  static const ocrNotReady = 'Yazı okuma henüz hazır değil';
  static const crossingNotReady = 'Karşıya geçiş modu henüz hazır değil';

  // --- Sesli komut ---------------------------------------------------------
  static const listening = 'Dinliyorum';
  static String heard(String text) => 'Şunu anladım: $text';
  static const listenCancelled = 'Dinleme iptal edildi';
  static const speechUnavailable =
      'Mikrofon izni verilmedi ya da konuşma tanıma bu cihazda kullanılamıyor';
  static const didNotHear = 'Sizi duyamadım, tekrar deneyin';
  static const speechNeedsInternet = 'Konuşma tanıma için internet bağlantısı gerekiyor';
  static const micPermissionDenied = 'Mikrofon izni verilmedi';
  static const turkishUnavailable = 'Türkçe konuşma tanıma bu cihazda kullanılamıyor';
  static const recognizerBusy = 'Konuşma tanıma meşgul, biraz sonra tekrar deneyin';
  static const recognitionFailed = 'Konuşma tanınamadı, tekrar deneyin';
  static const voiceButton = 'Sesli Komut Ver';
  static const voiceButtonLabel = 'Sesli komut ver. Dokunun ve komutunuzu söyleyin.';
  static const voiceListeningButton = 'Dinleniyor… Durdurmak için dokunun';
  static const voiceListeningLabel = 'Dinleniyor. Durdurmak için dokunun.';
  static const voiceProcessingButton = 'Komut işleniyor…';
  static const voiceProcessingLabel = 'Komut işleniyor, lütfen bekleyin.';
  static String lastHeard(String text) => 'Son duyulan: "$text"';

  // --- Test modu -----------------------------------------------------------
  static const manualOnlySimulated =
      'Elle komut gönderme sadece simülasyon modundayken çalışır. '
      'Bağlantı ekranından "Simülasyon modu"nu açın. '
      'Sesli komut her iki modda da çalışır.';
  static const intentLabel = 'Niyet (intent)';
  static const entityLabel = 'Entity (isim/yer, opsiyonel)';
  static const entityHint = 'örn. Emre, Kadıköy iskelesi';
  static const sendCommand = 'Komutu gönder';
  static const feedbackTest = 'Geri bildirim testi';
  static const hapticPatternLabel = 'Titreşim deseni';
  static const playHaptic = 'Titreşimi çal';
  static const earconLabel = 'Kısa ses';
  static const playEarcon = 'Kısa sesi çal';
  static const priorityTest = 'Duyuru önceliğini dene';
  static const priorityTestLabel =
      'Duyuru önceliğini dene. Önce sıradan bir duyuru başlar, '
      'ardından kritik bir duyuru onu keser.';
  static const priorityTestLow = 'Bu düşük öncelikli bir bilgi duyurusudur ve kesilmeden önce biraz uzun sürer.';
  static const priorityTestNormal = 'Bu sıradan bir komut sonucudur.';
  static const priorityTestCritical = 'Kritik duyuru: önünüzde engel var.';
  static const obstacleSimulation = 'Engel titreşimi simülasyonu';
  static const obstacleDistance = 'Engel mesafesi';
  static String meters(double m) => '${m.toStringAsFixed(1).replaceAll('.', ',')} metre';
  static const obstacleNone = 'Engel yok';

  static String hapticName(String id) => switch (id) {
        'connected' => 'Bağlandı',
        'disconnected' => 'Koptu',
        'batteryLow' => 'Pil düşük',
        'listening' => 'Dinliyorum',
        'understood' => 'Anlaşıldı',
        'notUnderstood' => 'Anlaşılamadı',
        'error' => 'Hata',
        'obstacle' => 'Engel',
        'turnLeft' => 'Sola dön',
        'turnRight' => 'Sağa dön',
        _ => id,
      };

  static String earconName(String id) => switch (id) {
        'listenStart' => 'Dinleme başladı',
        'listenEnd' => 'Dinleme bitti',
        'success' => 'Başarılı',
        'error' => 'Hata',
        _ => id,
      };

  // --- Ayarlar -------------------------------------------------------------
  static const settingsSpeech = 'Konuşma';
  static const settingsListening = 'Dinleme';
  static const settingsFeedback = 'Bildirimler';
  static const speechRate = 'Konuşma hızı';
  static const pitch = 'Ses tonu';
  static const silenceTimeout = 'Sessizlik süresi';
  static const silenceTimeoutHint =
      'Konuşmanız bittikten sonra bu kadar sessizlik olunca dinleme biter.';
  static const verbosity = 'Ayrıntı seviyesi';
  static const hapticStrength = 'Titreşim şiddeti';
  static const feedbackMode = 'Bildirim türü';
  static const resetSettings = 'Varsayılan ayarlara dön';
  static const settingsReset = 'Ayarlar varsayılana döndü';
  static String seconds(int s) => '$s saniye';

  static const speechRateNames = ['Çok yavaş', 'Yavaş', 'Normal', 'Hızlı', 'Çok hızlı'];
  static const pitchNames = ['Kalın', 'Normal', 'İnce'];
  static const verbosityShort = 'Kısa';
  static const verbosityShortHint = 'Sadece sonuç söylenir.';
  static const verbosityLong = 'Uzun';
  static const verbosityLongHint = 'Sonuçla birlikte ne yapmanız gerektiği de söylenir.';
  static const hapticNames = ['Kapalı', 'Hafif', 'Orta', 'Güçlü'];
  static const feedbackSpeech = 'Sesli bildirim';
  static const feedbackSpeechHint = '"Dinliyorum" gibi durumlar sesle söylenir.';
  static const feedbackEarcon = 'Sadece kısa ses';
  static const feedbackEarconHint =
      'Durumlar kısa seslerle bildirilir. Komut sonuçları yine okunur.';

  static String settingChanged(String setting, String value) => '$setting: $value';
  static String settingOption(String setting, String value) => '$setting: $value';
  static String settingUnchanged(String setting, String value) =>
      '$setting zaten ${value.toLowerCase()}';
  static const hapticOff = 'Titreşim kapatıldı';
}
