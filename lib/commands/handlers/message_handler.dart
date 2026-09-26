import 'dart:async';

import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../l10n/turkish_suffix.dart';
import '../../platform/direct_actions.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/message_flow.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import '../sent_messages.dart';
import '../url_opener.dart';
import 'contact_lookup.dart';

/// MESAJ niyeti. phone_bridge.py'deki simüle "SEND_MESSAGE" eyleminin
/// gerçek karşılığı.
///
/// Diyalog yöneticisi verildiyse (uygulamada her zaman) çok adımlı akışı
/// başlatır: kişi, mesaj metni (dikte), geri okuma ve onay (bkz.
/// MessageFlow). Onaydan sonra:
/// - "direct" derleme türünde (ve SMS izni varsa): doğrudan gönderir; tüm
///   parçalar operatöre ulaşınca "gönderildi" der.
/// - "play" türünde ya da izin yoksa: SMS uygulaması metin DOLU açılır,
///   gönder tuşuna kullanıcı basar.
class MessageHandler {
  final ContactResolver _contacts;
  final DialogManager? _dialogs;
  final UrlOpener _openUrl;
  final DirectActions _direct;
  final Future<bool> Function() _ensureSmsPermission;
  final SentMessageLog _sent;

  MessageHandler({
    ContactResolver? contacts,
    DialogManager? dialogs,
    UrlOpener? openUrl,
    DirectActions direct = const NoDirectActions(),
    Future<bool> Function()? ensureSmsPermission,
    SentMessageLog? sent,
  })  : _contacts = contacts ?? ContactResolver(),
        _dialogs = dialogs,
        _openUrl = openUrl ?? defaultOpenUrl,
        _direct = direct,
        _ensureSmsPermission = ensureSmsPermission ?? (() async => false),
        _sent = sent ?? SentMessageLog();

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

  /// Mesajı gönderir: mümkünse doğrudan, değilse SMS ekranını metin dolu
  /// açarak.
  Future<ActionResult> send(ContactEntry contact, String? body) async {
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }
    final number = contact.phones.first.replaceAll(RegExp(r'[^\d+]'), '');
    final name = contact.displayName;

    var permissionDenied = false;
    if (body != null && body.isNotEmpty && await _direct.isAvailable()) {
      if (await _ensureSmsPermission()) {
        switch (await _direct.sendSms(number, body)) {
          case SmsSendStatus.sent:
            _sent.last = SentMessage(name, body, confirmedSent: true);
            return ActionResult.ok(Tr.smsSent(dative(name)));
          case SmsSendStatus.failed:
            return ActionResult.fail(Tr.smsSendFailed, detail: Tr.smsSendFailedDetail);
          case SmsSendStatus.timeout:
            return ActionResult.fail(Tr.smsSendTimeout, detail: Tr.smsSendTimeoutDetail);
          case SmsSendStatus.unavailable:
            break; // ekrana düş
        }
      } else {
        permissionDenied = true;
      }
    }

    // queryParameters boşlukları "+" yapar; bazı SMS uygulamaları bunu
    // olduğu gibi gösterir - metin elle kodlanıyor.
    final uri = Uri.parse(body == null || body.isEmpty
        ? 'sms:$number'
        : 'sms:$number?body=${Uri.encodeComponent(body)}');
    if (!await _openUrl(uri)) return ActionResult.fail(Tr.smsFailed);
    if (body == null) {
      return ActionResult.ok(Tr.smsOpened(name), detail: Tr.smsOpenedDetail);
    }
    // Gönder tuşuna basılıp basılmadığını bilmiyoruz: "hazırlanan" olarak.
    _sent.last = SentMessage(name, body, confirmedSent: false);
    return ActionResult.ok(
      Tr.smsReady(name),
      detail: permissionDenied ? Tr.directPermissionFallback : Tr.smsReadyDetail,
    );
  }
}
