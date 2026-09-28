/// SOS'u kim tetikledi. Kaynak iki şeyi belirler: geri sayım süresi ve
/// 112'nin aranıp aranamayacağı.
enum SosSource {
  /// Sesli "yardım", "imdat", "acil durum".
  voice,

  /// Gözlük uzun basışı.
  glasses,

  /// Düşme algılama (Faz 7c). Süre uzundur ve **112 hiç aranmaz**
  /// (yanlış pozitif riski en yüksek yer; bkz. CLAUDE.md Faz 7 kararları).
  fall;

  /// Bu kaynaktan tetiklenen SOS 112'yi **kendiliğinden** arayabilir mi
  /// (ayar açıksa)? Düşmede hayır; ama kullanıcı onaylı teklif her kaynakta var.
  bool get may112 => this != fall;
}

/// Geri sayımı kim iptal etti.
enum SosCancelSource { voice, glasses, screen }

/// SOS zamanlamaları ve sınırları tek yerde (gerçek kullanımda
/// ayarlanacak, bkz. CLAUDE.md "Bekleyen telefon testleri").
abstract final class SosConfig {
  /// Elle SOS. İptal varsayılanı GÖNDER: kullanıcı bir şey yapmazsa gider.
  static const manualCountdown = Duration(seconds: 7);

  /// Düşme kaynaklı SOS (7c'de kullanılacak). Otomatik 112 yoktur; SMS'lerden
  /// sonra yalnızca onaylı teklif ([offerDecisionWindow]) sunulur.
  static const fallCountdown = Duration(seconds: 25);

  /// Geri sayım bitince konum henüz yoksa en fazla bu kadar beklenir.
  static const locationGrace = Duration(seconds: 3);

  /// Konumsuz gönderildiyse takip SMS'i için konum yeniden denenir:
  /// [followUpAttempts] kez, aralarında [followUpInterval]. İlk başarıda
  /// TEK takip SMS'i atılır.
  static const followUpAttempts = 3;
  static const followUpInterval = Duration(seconds: 30);

  /// SMS'ler bitmeden arama başlatılmasın ama bir SMS takılırsa (operatör
  /// zaman aşımı 30 sn) arama da bu kadar geç kalmasın.
  static const smsWaitBeforeCall = Duration(seconds: 10);

  /// Başarıyla gönderilen bir SOS'tan sonra, sesli olmayan tetikleyicilerin
  /// tekrar tetikleyebilmesi için geçmesi gereken süre. İptal edilen ya da
  /// gönderilemeyen SOS'u SAYMAZ; sesli "yardım" bu sınırdan etkilenmez.
  static const rateLimit = Duration(seconds: 60);

  /// Ön kontrolde takılan SOS'ta (kişi yok, izin yok) "112'yi aramak için
  /// çift dokunun" teklifinin geçerlilik süresi; bekleyen başka işlem yoktur.
  static const offer112Window = Duration(seconds: 20);

  /// SMS sonuçları söylendikten sonra, kişi araması BAŞLAMADAN önce 112
  /// teklifine verilen kısa karar süresi. Düşme kaynaklı SOS'ta her zaman,
  /// diğerlerinde SMS'lerin hiçbiri gitmediyse sunulur. Bu pencerede çift
  /// dokunuş 112 onayıdır ("tekrar et" değil); onaylanırsa kişi aranmaz.
  static const offerDecisionWindow = Duration(seconds: 6);

  static const maxContacts = 3;

  static Duration countdownFor(SosSource source) =>
      source == SosSource.fall ? fallCountdown : manualCountdown;
}
