/// Bir komutun işlenmesi sonucu. [message] hem test ekranında log olarak
/// gösteriliyor hem kullanıcıya seslendiriliyor (bkz. FeedbackHub.result).
class ActionResult {
  final bool success;
  final String message;

  /// Sadece "uzun" ayrıntı seviyesinde okunan ek açıklama - genelde
  /// kullanıcının sonraki adımda ne yapması gerektiği.
  final String? detail;

  /// Sonuç seslendirilmez, yalnızca titreşimle bildirilir ("dur": asıl
  /// istenen sessizlik; "tekrar et": konuşmayı eylemin kendisi yapıyor).
  final bool silent;

  /// İş çok adımlı bir diyaloğa devredildi: şimdi ne ses ne titreşim ne
  /// kayıt - sonucu diyalog bitince AppState kaydedip duyuruyor.
  final bool handedOff;

  const ActionResult({
    required this.success,
    required this.message,
    this.detail,
    this.silent = false,
    this.handedOff = false,
  });

  factory ActionResult.handedOff(String message) =>
      ActionResult(success: true, message: message, handedOff: true);

  factory ActionResult.ok(String message, {String? detail}) =>
      ActionResult(success: true, message: message, detail: detail);

  /// [message] sadece işlem geçmişinde görünür, okunmaz.
  factory ActionResult.silentOk(String message) =>
      ActionResult(success: true, message: message, silent: true);

  factory ActionResult.fail(String message, {String? detail}) =>
      ActionResult(success: false, message: message, detail: detail);
}
