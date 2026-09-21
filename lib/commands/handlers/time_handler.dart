import '../action_result.dart';

/// SAAT niyeti. Python main.py'de zaten phone_bridge'e hiç uğramadan yerel
/// saat üretiliyordu (phone_bridge.isle) - burada da aynı davranış: hiçbir
/// telefon eylemi/izin gerektirmiyor, sadece cihaz saatini okuyor.
class TimeHandler {
  Future<ActionResult> handle(String? entity) async {
    final now = DateTime.now();
    final saat = now.hour.toString().padLeft(2, '0');
    final dakika = now.minute.toString().padLeft(2, '0');
    return ActionResult.ok('Saat $saat:$dakika');
  }
}
