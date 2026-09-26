import 'dart:async';

import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/call_flow.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import '../url_opener.dart';
import 'contact_lookup.dart';

/// ARA niyeti. phone_bridge.py'deki simüle "CALL" eyleminin gerçek karşılığı.
///
/// Diyalog yöneticisi verildiyse (uygulamada her zaman) çok adımlı akışı
/// başlatır: kişi eksikse sorar, belirsizse "hangisi?" der, aramadan önce
/// onay alır (bkz. CallFlow). Verilmediyse (eski testler) tek adımda arar.
///
/// Karar (kullanıcı onayı): doğrudan arama YAPMIYOR - telefonun native arama
/// uygulamasını numarayla dolu şekilde açıyor (tel: URI). Android'de bu
/// ACTION_DIAL'a denk düşer (CALL_PHONE izni GEREKMEZ); doğrudan arama Faz 4'te
/// bayrak arkasında.
class CallHandler {
  final ContactResolver _contacts;
  final DialogManager? _dialogs;
  final UrlOpener _openUrl;

  CallHandler({ContactResolver? contacts, DialogManager? dialogs, UrlOpener? openUrl})
      : _contacts = contacts ?? ContactResolver(),
        _dialogs = dialogs,
        _openUrl = openUrl ?? defaultOpenUrl;

  Future<ActionResult> handle(String? entity) async {
    final dialogs = _dialogs;
    if (dialogs != null) {
      // Diyalog dakikalar sürebilir; router'ı bekletmiyoruz. Sonucu diyalog
      // bitince AppState kaydedip duyuruyor.
      unawaited(dialogs.start(CallFlow(entity, _contacts, dial)));
      return ActionResult.handedOff('Arama diyaloğu başladı');
    }

    if (entity == null) return ActionResult.fail(Tr.callNoTarget);
    final (contact, failure) = await lookupContact(_contacts, entity);
    if (contact == null) return failure!;
    return dial(contact);
  }

  /// Arama ekranını kişinin ilk numarasıyla açar.
  Future<ActionResult> dial(ContactEntry contact) async {
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }
    final uri = Uri(scheme: 'tel', path: _digits(contact.phones.first));
    if (!await _openUrl(uri)) return ActionResult.fail(Tr.dialerFailed);
    return ActionResult.ok(Tr.dialerOpened(contact.displayName), detail: Tr.dialerOpenedDetail);
  }

  static String _digits(String number) => number.replaceAll(RegExp(r'[^\d+]'), '');
}
