import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import 'contact_lookup.dart';

/// ARA niyeti. phone_bridge.py'deki simüle "CALL" eyleminin gerçek karşılığı.
///
/// Karar (kullanıcı onayı): doğrudan arama YAPMIYOR - telefonun native arama
/// uygulamasını numarayla dolu şekilde açıyor (tel: URI). Android'de bu
/// ACTION_DIAL'a denk düşer (CALL_PHONE izni GEREKMEZ), iOS'ta zaten Apple
/// hiçbir şekilde sessiz arama izni vermiyor - iki platformda da kullanıcı
/// son onayı kendi verir.
class CallHandler {
  final ContactResolver _contacts;

  CallHandler({ContactResolver? contacts})
      : _contacts = contacts ?? ContactResolver();

  Future<ActionResult> handle(String? entity) async {
    if (entity == null) {
      return ActionResult.fail(Tr.callNoTarget);
    }

    // Takma ad, Türkçe ek atma ve bulanık eşleştirme (bkz. ContactMatcher).
    final (contact, failure) = await lookupContact(_contacts, entity);
    if (contact == null) return failure!;
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }

    final number = contact.phones.first;
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri);
    if (!launched) {
      return ActionResult.fail(Tr.dialerFailed);
    }
    return ActionResult.ok(Tr.dialerOpened(contact.displayName),
        detail: Tr.dialerOpenedDetail);
  }
}
