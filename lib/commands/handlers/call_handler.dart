import 'dart:async';

import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../platform/direct_actions.dart';
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
/// Onaydan sonra:
/// - "direct" derleme türünde (ve arama izni varsa): doğrudan arar
///   ("Ahmet Yılmaz aranıyor").
/// - "play" türünde ya da izin yoksa: arama ekranını numarayla açar (tel:
///   URI, CALL_PHONE gerekmez); kullanıcı arama tuşuna basar.
class CallHandler {
  final ContactResolver _contacts;
  final DialogManager? _dialogs;
  final UrlOpener _openUrl;
  final DirectActions _direct;
  final Future<bool> Function() _ensureCallPermission;

  CallHandler({
    ContactResolver? contacts,
    DialogManager? dialogs,
    UrlOpener? openUrl,
    DirectActions direct = const NoDirectActions(),
    Future<bool> Function()? ensureCallPermission,
  })  : _contacts = contacts ?? ContactResolver(),
        _dialogs = dialogs,
        _openUrl = openUrl ?? defaultOpenUrl,
        _direct = direct,
        _ensureCallPermission = ensureCallPermission ?? (() async => false);

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

  /// Kişinin ilk numarasını arar: mümkünse doğrudan, değilse arama ekranını
  /// açarak.
  Future<ActionResult> dial(ContactEntry contact) async {
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }
    final number = _digits(contact.phones.first);

    var permissionDenied = false;
    if (await _direct.isAvailable()) {
      if (await _ensureCallPermission()) {
        if (await _direct.call(number)) return ActionResult.ok(Tr.calling(contact.displayName));
      } else {
        permissionDenied = true;
      }
    }

    // "play" türü, izin yok ya da doğrudan arama başlatılamadı: ekranı aç.
    final uri = Uri(scheme: 'tel', path: number);
    if (!await _openUrl(uri)) return ActionResult.fail(Tr.dialerFailed);
    return ActionResult.ok(
      Tr.dialerOpened(contact.displayName),
      detail: permissionDenied ? Tr.directPermissionFallback : Tr.dialerOpenedDetail,
    );
  }

  static String _digits(String number) => number.replaceAll(RegExp(r'[^\d+]'), '');
}
