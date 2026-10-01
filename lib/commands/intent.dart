/// Gözlükten (Python intent_classifier.py / gemini_classifier.py ile birebir
/// aynı isimlerle) gelebilecek niyet kategorileri.
enum PatikaIntent {
  ara,
  mesaj,
  saat,
  oku,
  gecisModu,
  navigasyon,

  /// Telefon tarafı ayarları ("daha hızlı konuş") - Python tarafında yok,
  /// sadece telefon mikrofonundan gelir. Entity: [SettingAction] adı.
  ayar,

  /// "Mehmet'in numarasını söyle" - kişinin numarasını okur.
  numara,

  /// "gönderdiğim son mesajı oku" (Faz 4a).
  sonMesaj,

  /// "annemi Fatma Yılmaz olarak kaydet", "takma adları oku", "annem takma
  /// adını sil". Entity: "kaydet|A|B", "oku", "sil|A" (bkz. AliasHandler).
  takmaAd,

  /// "mesajlarımı oku" (Faz 4b) - bildirimden yakalanan, henüz bu komutla
  /// okunmamış mesajları okur. Python tarafında yok, yalnızca telefon
  /// mikrofonundan (AYAR gibi).
  mesajlarim,

  /// "son bildirimleri oku" (Faz 4b) - son yakalanan bildirimlerin (en fazla
  /// 20) yalnızca göndereni özetlenir. Python tarafında yok.
  sonBildirimler,

  /// Navigasyon kontrolü (Faz 6) - Python tarafında yok, yalnızca telefon
  /// mikrofonundan. "navigasyonu bitir": çalışan yönlendirmeyi kapatır.
  navigasyonBitir,

  /// "ne kadar kaldı": hedefe kalan mesafe ve yaklaşık süre.
  navigasyonKalan,

  /// "geçtim": karşıya geçiş duraklamasını bitirir (gözlük çift dokunuşu ve
  /// zaman aşımı ile birlikte dört çıkış kanalından biri). `crossing_mode.py`
  /// da aynı sözcüğü kullanıyor.
  gectim,

  /// Evrensel konuşma kontrolü (Faz 2) - telefon tarafına özgü. Bunlar
  /// "Şunu anladım" teyidi olmadan hemen uygulanır.
  dur,
  tekrar,
  komutlar,
  egitim,

  /// "Yardım", "imdat", "acil durum" - SOS geri sayımını başlatır (Faz 7,
  /// `lib/sos/`). `play` derlemesinde "bu sürümde gönderilemiyor" der. Diğer
  /// tüm niyetlerden önce denetlenir.
  sos,

  /// "acil kişi ekle/sil X", "acil kişiler kim" (Faz 7a-3) - SOS'un
  /// gönderdiği acil kişi listesini yönetir. Python tarafında yok, yalnızca
  /// telefon mikrofonundan. Entity: "ekle|X", "sil|X", "liste"
  /// (`EmergencyContactHandler`).
  acilKisi,

  /// "durum", "pil ne kadar" (Faz 7b): gözlük bağlantısı + iki pil + çalışan
  /// navigasyon özeti. Python tarafında yok, yalnızca telefon mikrofonundan.
  /// Kontrol niyeti değil (anında uygulanan DUR/SOS gibi değil), sıradan sorgu.
  durum,

  bilinmiyor;

  /// Anında (onay sorusu olmadan) uygulanan kontrol niyetleri. Telefon eylemi
  /// başlatan ARA/MESAJ/NAVİGASYON çok adımlı diyalogla onay alır.
  bool get isControl =>
      this == dur || this == tekrar || this == komutlar || this == egitim || this == sos;

  /// Python tarafındaki niyet string'ini (örn. "ARA", "GECIS_MODU") enum'a
  /// çevirir. Eşleşmeyen/bilinmeyen bir değer sessizce [bilinmiyor]'a düşer -
  /// glasses tarafı ileride yeni bir niyet eklerse companion app asla çökmez.
  static PatikaIntent fromWireName(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'ARA':
        return PatikaIntent.ara;
      case 'MESAJ':
        return PatikaIntent.mesaj;
      case 'SAAT':
        return PatikaIntent.saat;
      case 'OKU':
        return PatikaIntent.oku;
      case 'GECIS_MODU':
        return PatikaIntent.gecisModu;
      case 'NAVİGASYON':
      case 'NAVIGASYON':
        return PatikaIntent.navigasyon;
      case 'AYAR':
        return PatikaIntent.ayar;
      case 'NUMARA':
        return PatikaIntent.numara;
      case 'TAKMA_AD':
        return PatikaIntent.takmaAd;
      case 'SON_MESAJ':
        return PatikaIntent.sonMesaj;
      case 'MESAJLARIM':
        return PatikaIntent.mesajlarim;
      case 'SON_BİLDİRİMLER':
      case 'SON_BILDIRIMLER':
        return PatikaIntent.sonBildirimler;
      case 'NAV_BITIR':
        return PatikaIntent.navigasyonBitir;
      case 'NAV_KALAN':
        return PatikaIntent.navigasyonKalan;
      case 'GECTIM':
      case 'GEÇTİM':
        return PatikaIntent.gectim;
      case 'DUR':
        return PatikaIntent.dur;
      case 'TEKRAR':
        return PatikaIntent.tekrar;
      case 'KOMUTLAR':
        return PatikaIntent.komutlar;
      case 'EĞİTİM':
      case 'EGITIM':
        return PatikaIntent.egitim;
      case 'SOS':
        return PatikaIntent.sos;
      case 'ACIL_KİŞİ':
      case 'ACIL_KISI':
        return PatikaIntent.acilKisi;
      case 'DURUM':
        return PatikaIntent.durum;
      default:
        return PatikaIntent.bilinmiyor;
    }
  }
}
