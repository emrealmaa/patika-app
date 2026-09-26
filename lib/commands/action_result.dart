/// Bir komutun işlenmesi sonucu. [message] hem test ekranında log olarak
/// gösteriliyor hem kullanıcıya seslendiriliyor (bkz. FeedbackHub.result).
class ActionResult {
  final bool success;
  final String message;

  /// Sadece "uzun" ayrıntı seviyesinde okunan ek açıklama - genelde
  /// kullanıcının sonraki adımda ne yapması gerektiği.
  final String? detail;

  const ActionResult({required this.success, required this.message, this.detail});

  factory ActionResult.ok(String message, {String? detail}) =>
      ActionResult(success: true, message: message, detail: detail);

  factory ActionResult.fail(String message, {String? detail}) =>
      ActionResult(success: false, message: message, detail: detail);
}
