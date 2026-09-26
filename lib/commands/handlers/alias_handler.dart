import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../contact_resolver.dart';

/// TAKMA_AD niyeti. Entity biçimi (sınıflandırıcı üretir):
/// - "kaydet|A|B": A ile B'den biri rehberdeki kişi, diğeri takma ad.
///   Türkçe'de iki sıra da doğal ("annemi Fatma Yılmaz olarak kaydet" /
///   "Fatma Yılmaz'ı annem olarak kaydet"); hangisinin kişi olduğuna
///   rehbere bakılarak karar verilir.
/// - "oku": kayıtlı takma adları okur.
/// - "sil|A": takma adı siler.
class AliasHandler {
  final ContactResolver _contacts;

  AliasHandler({ContactResolver? contacts}) : _contacts = contacts ?? ContactResolver();

  Future<ActionResult> handle(String? entity) async {
    final parts = (entity ?? '').split('|');
    switch (parts.first) {
      case 'kaydet' when parts.length == 3:
        return _save(parts[1].trim(), parts[2].trim());
      case 'oku':
        return _list();
      case 'sil' when parts.length == 2 && parts[1].trim().isNotEmpty:
        final alias = parts[1].trim();
        final removed = await _contacts.aliases.remove(alias);
        return removed
            ? ActionResult.ok(Tr.aliasRemoved(alias))
            : ActionResult.fail(Tr.aliasMissing(alias));
      default:
        return ActionResult.fail(Tr.aliasNotUnderstood);
    }
  }

  Future<ActionResult> _save(String a, String b) async {
    if (a.isEmpty || b.isEmpty) return ActionResult.fail(Tr.aliasNotUnderstood);

    final matchA = await _contacts.resolveInContacts(a);
    final matchB = await _contacts.resolveInContacts(b);
    if (matchA is ContactPermissionDenied || matchB is ContactPermissionDenied) {
      return ActionResult.fail(Tr.contactsPermissionDenied);
    }

    // Kişi olan taraf: tek bir kişiye çözülen. İkisi de çözülürse (rehberde
    // "Annem" adlı biri de varsa) daha çok kelimeli olan kişidir - takma
    // adlar genelde tek kelime (annem, babam), rehber adları ad soyad.
    // Eşitse "... olarak" öncesindeki (B).
    final bIsContact = switch ((matchA, matchB)) {
      (ContactFound(), ContactFound()) => _words(b) >= _words(a),
      (_, ContactFound()) => true,
      (ContactFound(), _) => false,
      (ContactAmbiguous(), ContactAmbiguous()) => _words(b) >= _words(a),
      (_, ContactAmbiguous()) => true,
      (ContactAmbiguous(), _) => false,
      _ => true,
    };
    final alias = bIsContact ? a : b;
    final match = bIsContact ? matchB : matchA;

    switch (match) {
      case ContactFound(:final contact):
        await _contacts.aliases.save(alias, AliasTarget(contact.id, contact.displayName));
        return ActionResult.ok(Tr.aliasSaved(alias, contact.displayName));
      case ContactAmbiguous(:final candidates):
        return ActionResult.fail(Tr.contactAmbiguous([for (final c in candidates) c.displayName]));
      default:
        return ActionResult.fail(Tr.contactNotFound(bIsContact ? b : a),
            detail: Tr.contactNotFoundDetail);
    }
  }

  static int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

  Future<ActionResult> _list() async {
    final all = await _contacts.aliases.readAll();
    if (all.isEmpty) return ActionResult.ok(Tr.aliasNone);
    return ActionResult.ok(Tr.aliasList([
      for (final e in all.entries) '${e.key}, ${e.value.displayName}',
    ]));
  }
}
