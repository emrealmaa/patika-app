import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import 'contact_lookup.dart';

/// NUMARA niyeti: "Mehmet'in numarasını söyle" - numarayı rakam rakam,
/// gruplar halinde okur ("0 5 3 2, 1 2 3, 4 5, 6 7"). TTS rakamları tek
/// tek okur; gruplar arasındaki virgül kısa bir duraklama yaratır - görme
/// engelli kullanıcı numarayı ezberleyebilsin/yazdırabilsin.
class NumberHandler {
  final ContactResolver _contacts;

  NumberHandler({ContactResolver? contacts}) : _contacts = contacts ?? ContactResolver();

  Future<ActionResult> handle(String? entity) async {
    if (entity == null) return ActionResult.fail(Tr.numberNoTarget);

    final (contact, failure) = await lookupContact(_contacts, entity);
    if (contact == null) return failure!;
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }
    return ActionResult.ok(Tr.numberIs(contact.displayName, spokenDigits(contact.phones.first)));
  }

  /// "+90 532 123 45 67" -> "artı 9 0, 5 3 2, 1 2 3, 4 5, 6 7"
  /// "0532 123 4567"     -> "0 5 3 2, 1 2 3, 4 5, 6 7"
  static String spokenDigits(String number) {
    final plus = number.trim().startsWith('+');
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return number;

    final groups = <String>[];
    var rest = digits;
    if (plus && rest.startsWith('90') && rest.length == 12) {
      // Türkiye cep: +90 5xx xxx xx xx
      groups.add('90');
      rest = rest.substring(2);
    }
    if (rest.length == 11 && rest.startsWith('0')) {
      groups.addAll([rest.substring(0, 4), rest.substring(4, 7), rest.substring(7, 9), rest.substring(9)]);
    } else if (rest.length == 10) {
      groups.addAll([rest.substring(0, 3), rest.substring(3, 6), rest.substring(6, 8), rest.substring(8)]);
    } else {
      for (var i = 0; i < rest.length; i += 3) {
        groups.add(rest.substring(i, i + 3 > rest.length ? rest.length : i + 3));
      }
    }
    final spoken = groups.map((g) => g.split('').join(' ')).join(', ');
    return plus ? 'artı $spoken' : spoken;
  }
}
