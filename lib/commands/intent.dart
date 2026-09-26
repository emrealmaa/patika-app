/// Gözlükten (Python intent_classifier.py / gemini_classifier.py ile birebir
/// aynı isimlerle) gelebilecek niyet kategorileri.
enum PatikaIntent {
  ara,
  mesaj,
  hava,
  saat,
  muzik,
  haber,
  oku,
  gecisModu,
  navigasyon,

  /// Telefon tarafı ayarları ("daha hızlı konuş") - Python tarafında yok,
  /// sadece telefon mikrofonundan gelir. Entity: [SettingAction] adı.
  ayar,

  /// "Mehmet'in numarasını söyle" - kişinin numarasını okur.
  numara,

  /// "annemi Fatma Yılmaz olarak kaydet", "takma adları oku", "annem takma
  /// adını sil". Entity: "kaydet|A|B", "oku", "sil|A" (bkz. AliasHandler).
  takmaAd,

  /// Evrensel konuşma kontrolü (Faz 2) - telefon tarafına özgü. Bunlar
  /// "Şunu anladım" teyidi olmadan hemen uygulanır.
  dur,
  tekrar,
  komutlar,
  egitim,

  /// "Yardım", "imdat", "acil durum" - Faz 7'de SOS akışı; o zamana kadar
  /// hazır olmadığını söyler. Diğer tüm niyetlerden önce denetlenir.
  sos,
  bilinmiyor;

  /// Sesli komutta "Şunu anladım: ..." teyidi söylenecek niyetler: gerçek
  /// bir telefon eylemi başlatanlar. Yanlış duyulan bir isim yanlış kişinin
  /// aranmasına yol açmasın - bu bir güvenlik önlemi, bilgi tercihi değil
  /// (ayrıntı seviyesinden bağımsız). Bilgi veren komutlarda sonucun kendisi
  /// ("Saat 14:05") neyin anlaşıldığını zaten gösteriyor.
  ///
  /// ARA/MESAJ'da bu teyidin yerini Faz 3b'de gerçek onay diyaloğu aldı
  /// ("Ahmet Yılmaz'ı arayayım mı?"). NAVİGASYON'da Faz 6'ya kadar kalıyor.
  bool get needsConfirmation => this == navigasyon;

  /// "Şunu anladım: ..." teyidi olmadan anında uygulanan kontrol niyetleri.
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
      case 'HAVA':
        return PatikaIntent.hava;
      case 'SAAT':
        return PatikaIntent.saat;
      case 'MÜZİK':
      case 'MUZIK':
        return PatikaIntent.muzik;
      case 'HABER':
        return PatikaIntent.haber;
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
      default:
        return PatikaIntent.bilinmiyor;
    }
  }
}
