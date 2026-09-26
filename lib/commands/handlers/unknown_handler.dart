import '../../l10n/strings_tr.dart';
import '../action_result.dart';

/// BİLİNMİYOR niyeti (ya da hiçbir kategoriye eşleşmeyen, bilinmeyen bir
/// wire değeri - bkz. PatikaIntent.fromWireName). phone_bridge.isle()'deki
/// "Bu komutu anlayamadım" davranışının karşılığı.
class UnknownHandler {
  /// [entity] sesli komutta duyulan metindir (varsa): "Şunu anladım" +
  /// "anlayamadım" iki cümle yerine tek cümlede söyleniyor.
  Future<ActionResult> handle(String? entity) async {
    if (entity == null || entity.trim().isEmpty) {
      return ActionResult.fail(Tr.unknownCommand);
    }
    return ActionResult.fail(Tr.unknownCommandHeard(entity.trim()));
  }
}
