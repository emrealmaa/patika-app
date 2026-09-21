/// Bir komutun işlenmesi sonucu. `message`, test ekranında log olarak
/// gösteriliyor - ileride TTS ile seslendirmek için de aynı alan kullanılabilir.
class ActionResult {
  final bool success;
  final String message;

  const ActionResult({required this.success, required this.message});

  factory ActionResult.ok(String message) =>
      ActionResult(success: true, message: message);

  factory ActionResult.fail(String message) =>
      ActionResult(success: false, message: message);
}
