import 'dart:async';

import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/message_flow.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import '../url_opener.dart';
import 'contact_lookup.dart';

/// MESAJ niyeti. phone_bridge.py'deki simüle "SEND_MESSAGE" eyleminin
/// gerçek karşılığı.
///
/// Diyalog yöneticisi verildiyse (uygulamada her zaman) çok adımlı akışı
/// başlatır: kişi, mesaj metni (dikte), geri okuma ve onay (bkz.
/// MessageFlow). SMS uygulaması metin DOLU açılır, gönder tuşuna kullanıcı
/// basar (onaylı Faz 3 kararı); SmsManager ile doğrudan gönderme Faz 4'te
/// bayrak arkasında.
class MessageHandler {
  final ContactResolver _contacts;
  final DialogManager? _dialogs;
  final UrlOpener _openUrl;

  MessageHandler({ContactResolver? contacts, DialogManager? dialogs, UrlOpener? openUrl})
      : _contacts = contacts ?? ContactResolver(),
        _dialogs = dialogs,
        _openUrl = openUrl ?? defaultOpenUrl;

  Future<ActionResult> handle(String? entity) async {
    final dialogs = _dialogs;
    if (dialogs != null) {
      unawaited(dialogs.start(MessageFlow(entity, _contacts, send)));
      return ActionResult.handedOff('Mesaj diyaloğu başladı');
    }

    if (entity == null) return ActionResult.fail(Tr.messageNoTarget);
    final (contact, failure) = await lookupContact(_contacts, entity);
    if (contact == null) return failure!;
    return send(contact, null);
  }

  /// SMS ekranını kişinin numarasıyla ve (varsa) metin dolu açar.
  Future<ActionResult> send(ContactEntry contact, String? body) async {
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }
    final number = contact.phones.first.replaceAll(RegExp(r'[^\d+]'), '');
    // queryParameters boşlukları "+" yapar; bazı SMS uygulamaları bunu
    // olduğu gibi gösterir - metin elle kodlanıyor.
    final uri = Uri.parse(body == null || body.isEmpty
        ? 'sms:$number'
        : 'sms:$number?body=${Uri.encodeComponent(body)}');
    if (!await _openUrl(uri)) return ActionResult.fail(Tr.smsFailed);
    return body == null
        ? ActionResult.ok(Tr.smsOpened(contact.displayName), detail: Tr.smsOpenedDetail)
        : ActionResult.ok(Tr.smsReady(contact.displayName), detail: Tr.smsReadyDetail);
  }
}
