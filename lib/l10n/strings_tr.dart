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
  static String unknownCommandHeard(String heard) => '"$heard" komutunu anlayamadım';

  // --- Bağlantı ------------------------------------------------------------
  static const glassesConnected = 'Gözlük bağlandı';
  static const glassesDisconnected = 'Gözlük bağlantısı koptu';
  static const glassesDisconnectedByUser = 'Gözlük bağlantısı kesildi';
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
  static const cannotReachGlasses = 'Gözlüğe bağlanılamıyor, denemeye devam ediyorum';
  static String batteryVisual(int percent) => 'Gözlük pili: %$percent';
  static String batterySpoken(int percent) => 'gözlük pili yüzde $percent';

  // --- Gözlük olayları -----------------------------------------------------
  static const buttonTap = 'Tek dokunuş';
  static const buttonDoubleTap = 'Çift dokunuş';
  static const buttonLongPress = 'Uzun basış';
  static const gestureDoubleNod = 'Çift baş sallama';
  static String glassesEvent(String event) => 'Gözlük: $event';

  // --- Arka plan servisi ---------------------------------------------------
  static const notificationChannel = 'Patika bağlantısı';
  static const notificationChannelDescription =
      'Gözlük bağlantısının arka planda sürmesi için kalıcı bildirim';
  static const notificationTitle = 'Patika';
  static const notificationConnected = 'Patika gözlüğe bağlı';
  static const notificationSearching = 'Gözlük aranıyor';
  static const notificationDisconnected = 'Gözlük bağlı değil';

  // --- İzinler -------------------------------------------------------------
  static const notificationPermissionWhy =
      'Gözlük bağlantısı ekran kapalıyken de sürsün diye bildirim izni isteyeceğim.';
  static const bluetoothPermissionWhy =
      'Gözlüğü bulup bağlanabilmem için Bluetooth izni isteyeceğim.';
  static const permissionDenied = 'İzin verilmedi. Ayarlardan daha sonra verebilirsiniz.';
  static const permissionPermanentlyDenied =
      'Bu izin daha önce reddedildi. Telefon ayarlarından, uygulamalar bölümünden Patika için izin verebilirsiniz.';

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
  static const contactsPermissionWhy =
      'Söylediğiniz kişiyi rehberinizde bulabilmem için rehber izni isteyeceğim.';
  static const contactsPermissionDenied = 'Rehber izni olmadan kişileri bulamıyorum';
  /// Faz 3b'deki "hangisi?" diyaloğuna kadar geçici.
  static String contactAmbiguous(List<String> names) =>
      '${names.length} kişi buldum: ${names.join(', ')}. Lütfen tam adını söyleyin.';
  static const numberNoTarget = 'Kimin numarasını istediğinizi anlayamadım';

  // --- Diyalog (Faz 3b) ------------------------------------------------------
  static const dialogCancelled = 'İptal ettim';
  static const dialogTimedOut = 'Cevap alamadım, iptal ettim';
  static const dialogNotUnderstood = 'Anlayamadım, iptal ettim';
  static const dialogDidNotHear = 'Sizi duyamadım.';
  static const dialogWhoToCall = 'Kimi arayayım?';
  static const dialogWhoToMessage = 'Kime mesaj göndereyim?';
  static const dialogWhatToWrite = 'Ne yazayım?';
  static String dialogNotFound(String nameAccusative, String question) =>
      '$nameAccusative rehberde bulamadım. $question';
  static const _countWords = {2: 'İki', 3: 'Üç'};
  static const _ordinalWords = ['birinci', 'ikinci', 'üçüncü'];
  static String dialogChoose(List<String> names) {
    final listed = [
      for (var i = 0; i < names.length && i < _ordinalWords.length; i++)
        '${_ordinalWords[i]} ${names[i]}',
    ];
    return '${_countWords[names.length] ?? names.length} kişi buldum: '
        '${listed.join(', ')}. Hangisi?';
  }
  static String dialogConfirmCall(String nameAccusative) => '$nameAccusative arayayım mı?';
  static String dialogConfirmMessage(String nameDative, String body) =>
      '$nameDative şu mesaj: $body. Göndereyim mi?';
  static const dialogYesNoHint = 'Evet ya da hayır deyin.';
  static const dialogChoiceHint = 'Birinci, ikinci ya da soyadını söyleyin.';
  static const dialogReviewHint =
      'Göndermek için evet, değiştirmek için düzelt, iptal için hayır deyin.';
  static String smsReady(String name) => '$name için mesaj hazır';

  // --- Doğrudan arama / SMS (Faz 4a, "direct" derleme türü) -----------------
  static String calling(String name) => '$name aranıyor';
  static const callPermissionWhy =
      'Onayladığınız kişiyi doğrudan arayabilmem için arama izni isteyeceğim.';
  static const smsPermissionWhy =
      'Onayladığınız mesajı sizin yerinize gönderebilmem için SMS izni isteyeceğim.';
  static const directPermissionFallback =
      'İzin olmadığı için ekranı açtım, tuşa sizin basmanız gerekiyor.';
  static String smsSent(String nameDative) => '$nameDative mesaj gönderildi';
  static const smsSendFailed = 'Mesaj gönderilemedi';
  static const smsSendFailedDetail = 'Şebeke olmayabilir. Biraz sonra tekrar deneyin.';
  static const smsSendTimeout = 'Mesajın gidip gitmediğini doğrulayamadım';
  static const smsSendTimeoutDetail = 'Mesajlar uygulamasından kontrol edin.';
  static const lastSentNone = 'Henüz bir mesaj göndermedim';
  static String lastSent(String nameDative, String body) =>
      '$nameDative gönderilen son mesaj: $body';
  static String lastPrepared(String name, String body) =>
      '$name için hazırlanan son mesaj: $body';
  static const lastPreparedDetail =
      'Bu sürümde mesajın gönderilip gönderilmediğini bilemiyorum.';
  static const smsReadyDetail = 'Göndermek için ekrandaki gönder tuşuna basın.';
  static String numberIs(String name, String spokenDigits) => '$name: $spokenDigits';
  static const aliasNotUnderstood =
      'Takma adı ve kişiyi anlayamadım. Örneğin: annemi Fatma Yılmaz olarak kaydet.';
  static String aliasSaved(String alias, String name) =>
      'Tamam. $alias dediğinizde $name anlayacağım';
  static const aliasNone = 'Kayıtlı takma ad yok';
  static String aliasList(List<String> entries) => 'Takma adlar: ${entries.join('. ')}';
  static String aliasRemoved(String alias) => '$alias takma adı silindi';
  static String aliasMissing(String alias) => '$alias adında bir takma ad yok';
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

  // --- Gelen arama (Faz 4b) --------------------------------------------------
  static String incomingCall(String callerName) => '$callerName arıyor';
  static String callAnswered(String callerName) => '$callerName ile görüşme açılıyor';
  static String callRejected(String callerName) => '$callerName için gelen arama reddedildi';
  static const notificationAccessWhy =
      'Gelen arama ve mesaj bildirimlerini okuyabilmem için bildirim '
      'erişimi izni gerekiyor. Şimdi ayarlar açılacak, listede Patika\'yı '
      'bulup açın.';
  static String incomingMessage(String senderAblative, String body) =>
      '$senderAblative mesaj: $body';
  static String incomingMessageSenderOnly(String senderAblative) =>
      '$senderAblative yeni mesaj';
  static const loudMessagesNotice =
      'Mesaj içerikleri yüksek sesle okunuyor, kalabalık ortamda dikkat '
      'edin, ayarlardan kapatabilirsiniz.';
  static const readMessagesAloud = 'Mesaj içeriklerini yüksek sesle oku';
  static const readMessagesAloudHint =
      'Kapatırsanız yalnızca kimden geldiği söylenir, içerik okunmaz.';
  static const noNewMessages = 'Yeni mesaj yok';
  static String newMessages(List<String> lines) => lines.join('. ');
  static const noRecentNotifications = 'Hiç bildirim yok';
  static String recentNotifications(List<String> senders) =>
      'Son bildirimler: ${senders.join(', ')}';
  static const notificationsMuted = 'Bildirimler susturuldu';
  static const notificationsUnmuted = 'Bildirimler açıldı';
  static const muteNotifications = 'Bildirimleri sustur';
  static const muteNotificationsHint =
      'Açıkken gelen mesaj bildirimleri hiç seslendirilmez (yine de '
      '"mesajlarımı oku" ile okunabilir). Gelen aramalar bundan etkilenmez.';

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

  static const micPermissionWhy =
      'Komutlarınızı dinleyebilmem için mikrofon izni isteyeceğim.';

  // --- Konuş sekmesi -------------------------------------------------------
  static const tabListen = 'Konuş';
  static String glassesStatusLine(bool connected) =>
      connected ? 'Gözlük bağlı' : 'Gözlük bağlı değil';

  // --- Evrensel komutlar ---------------------------------------------------
  static const helpShort = 'Şunları söyleyebilirsiniz: bir kişiyi ara, mesaj gönder, '
      'bir yere götür, saat kaç, daha hızlı konuş, tekrar et, dur ve eğitimi başlat.';
  static const helpDetail = 'Örneğin: Ahmet\'i ara. Ayşe\'ye mesaj gönder. '
      'Kadıköy iskelesine götür. Konuşmamı kesmek için dur, '
      'son söylediğimi duymak için tekrar et deyin ya da gözlük butonuna iki kez dokunun.';
  static const nothingToRepeat = 'Tekrar edilecek bir şey yok';
  static const sosNotReady = 'Acil durum özelliği henüz hazır değil. '
      'Komutları duymak için ne yapabilirim deyin.';

  // --- Sesli eğitim --------------------------------------------------------
  static const tutorialSteps = [
    'Patika\'ya hoş geldiniz. Size uygulamayı kısaca tanıtacağım. '
        'Durdurmak için gözlük butonuna ya da ekrandaki Konuş alanına dokunun.',
    'Gözlüğünüzü açtığınızda telefon onu kendisi bulur ve bağlanır. '
        'Bağlantı kurulunca gözlük bağlandı, koparsa gözlük bağlantısı koptu diye haber veririm.',
    'Komut vermek için gözlüğün butonuna bir kez dokunun ya da uygulamadaki '
        'Konuş alanına dokunun. Kısa bir ses duyunca komutunuzu söyleyin.',
    'Örneğin Ahmet\'i ara, Ayşe\'ye mesaj gönder, Kadıköy iskelesine götür '
        'ya da saat kaç diyebilirsiniz.',
    'Konuşmamı kesmek için dur deyin. Son söylediğimi tekrar duymak için tekrar et deyin '
        'ya da gözlük butonuna iki kez dokunun. Tüm komutlar için ne yapabilirim deyin.',
    'Konuşma hızımı daha hızlı konuş ya da daha yavaş konuş diyerek değiştirebilirsiniz.',
  ];
  static const tutorialDone =
      'Eğitim bitti. Tekrar dinlemek için eğitimi başlat deyin.';
  static const startTutorial = 'Sesli eğitimi başlat';

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
  static const glassesSimulation = 'Gözlük simülasyonu';
  static const glassesSimulationHint =
      'Gözlüğün buton, jest ve pil olaylarını ve bağlantı sorunlarını taklit eder.';
  static const glassesBattery = 'Gözlük pil seviyesi';
  static String percent(int p) => 'yüzde $p';
  static const heartbeatPaused = 'Gözlük donmuş gibi davransın';
  static const heartbeatPausedHint =
      'Gözlük sinyal göndermeyi keser. Birkaç saniye içinde bağlantı kopmuş sayılmalı.';
  static const glassesUnreachable = 'Gözlük menzil dışında';
  static const glassesUnreachableHint =
      'Bağlantı kopar ve yeniden bağlanma denemeleri başarısız olur.';
  static String lastHaptic(String name) => 'Gözlüğe giden son titreşim: $name';
  static const delayedTap = '5 saniye sonra dokun (arka plan testi)';
  static const delayedTapHint =
      'Bu sürede telefonu kilitleyin: ekran kapalıyken dinlemenin başlayıp başlamadığını dener.';
  static const incomingCallSimulation = 'Gelen arama simülasyonu';
  static const incomingCallSimulationHint =
      'Bildirim dinleyici henüz yok - burada arayan adı girip aramayı çaldırabilir, '
      'sonra gözlük butonuyla (dokun = aç, uzun bas = reddet) deneyebilirsiniz.';
  static const callerNameLabel = 'Arayan adı';
  static const callerNameHint = 'örn. Ahmet Yılmaz';
  static const startIncomingCall = 'Aramayı çaldır';
  static const noActiveCall = 'Çalan arama yok';
  static String activeCall(String callerName) => '$callerName arıyor (çalıyor)';
  static const notificationAccessTest = 'Bildirim erişimi (Faz 4b)';
  static const notificationAccessTestHint =
      'Gerçek bildirim dinleyici henüz yok - burada yalnızca erişim durumu '
      'kontrol edilip gerekirse ayar ekranı açılabilir.';
  static const notificationAccessEnabled = 'Bildirim erişimi: açık';
  static const notificationAccessDisabled = 'Bildirim erişimi: kapalı';
  static const checkNotificationAccess = 'Durumu kontrol et';
  static const requestNotificationAccess = 'İzni iste (ayarları aç)';

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
        'incomingCall' => 'Gelen arama',
        'incomingMessage' => 'Gelen mesaj',
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
  static const nodToListen = 'Baş sallayarak dinlet';
  static const nodToListenHint =
      'Başınızı iki kez sallayınca dinleme başlar. Yanlışlıkla tetiklenebileceği için varsayılan olarak kapalı.';
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
