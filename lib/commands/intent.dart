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
  bilinmiyor;

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
      default:
        return PatikaIntent.bilinmiyor;
    }
  }
}
