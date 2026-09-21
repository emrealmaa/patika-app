import '../action_result.dart';

/// BİLİNMİYOR niyeti (ya da hiçbir kategoriye eşleşmeyen, bilinmeyen bir
/// wire değeri - bkz. PatikaIntent.fromWireName). phone_bridge.isle()'deki
/// "Bu komutu anlayamadım" davranışının karşılığı.
class UnknownHandler {
  Future<ActionResult> handle(String? entity) async {
    return ActionResult.fail('Bu komutu anlayamadım');
  }
}
