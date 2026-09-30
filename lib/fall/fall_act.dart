/// Açık modda bir düşme adayına ne yapıldı (Faz 7c-2, karar 10). Gölge
/// kaydına (`act` alanı) yazılır: bir iptal, gerçek dünyadaki en güçlü
/// "yanlış pozitif" etiketidir ve eşik ayarında kullanılır. Konum ve ham veri
/// yoktur.
enum FallAct {
  /// Gölge ya da kapalı mod: hiçbir eylem yok (eski satırlar da böyle okunur).
  none,

  /// Geri sayım başladı (sonradan iptal edilebilir ya da gidebilir).
  started,

  /// Kullanıcı geri sayımı iptal etti.
  cancelled,

  /// Acil durum mesajı/araması gönderildi.
  sent,

  /// Acil durum akışı BAŞLATILMADI: bastırma, zaten süren bir akış, 60 sn sınırı
  /// ya da ön kontrolde takılma.
  suppressed,
}
