import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../contact_resolver.dart';

/// ARA/MESAJ/NUMARA'nın ortak adımı: söylenen adı tek bir kişiye çözer ya
/// da kullanıcıya ne olduğunu söyleyen bir sonuç döndürür.
///
/// Birden fazla eşleşme (iki Ahmet) Faz 3b'de "hangisi?" diyaloğuna
/// dönüşecek; şimdilik adaylar okunup tam ad isteniyor.
Future<(ContactEntry?, ActionResult?)> lookupContact(
  ContactResolver contacts,
  String spokenName,
) async {
  final match = await contacts.resolve(spokenName);
  switch (match) {
    case ContactFound(:final contact):
      return (contact, null);
    case ContactAmbiguous(:final candidates):
      return (
        null,
        ActionResult.fail(Tr.contactAmbiguous([for (final c in candidates) c.displayName])),
      );
    case ContactNotFound():
      return (
        null,
        ActionResult.fail(Tr.contactNotFound(spokenName), detail: Tr.contactNotFoundDetail),
      );
    case ContactPermissionDenied():
      return (null, ActionResult.fail(Tr.contactsPermissionDenied));
  }
}
