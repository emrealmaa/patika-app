/// Gelen mesaj bildirimi okunabilecek uygulamaların SABİT beyaz listesi.
/// Rastgele paket kabul edilmez: native dinleyici (`PatikaNotificationListener.kt`)
/// de yalnızca bu paketleri tanır. Yeni uygulama eklemek kod değişikliğidir.
enum MessageApp {
  /// Telefonun varsayılan SMS uygulaması (paket çalışma zamanında sorulur).
  sms(null),
  whatsapp('com.whatsapp'),
  whatsappBusiness('com.whatsapp.w4b'),
  telegram('org.telegram.messenger'),
  signal('org.thoughtcrime.securesms');

  /// Android paket adı; [sms] için null (varsayılan SMS uygulaması).
  final String? package;
  const MessageApp(this.package);

  /// Mevcut davranış (Faz 4b): varsayılan SMS + WhatsApp (kişisel + iş).
  static const defaults = {sms, whatsapp, whatsappBusiness};

  static MessageApp? fromName(String? name) {
    for (final a in values) {
      if (a.name == name) return a;
    }
    return null;
  }
}
