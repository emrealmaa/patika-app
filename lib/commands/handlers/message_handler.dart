import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings_tr.dart';
import '../action_result.dart';
import '../contact_resolver.dart';
import 'contact_lookup.dart';

/// MESAJ niyeti. phone_bridge.py'deki simüle "SEND_MESSAGE" eyleminin
/// gerçek karşılığı.
///
/// v1 KAPSAM KARARI: mesaj METNİ şu an hiçbir yerde yakalanmıyor - Python
/// tarafındaki intent_classifier/gemini_classifier de sadece alıcı ismini
/// (`entity`) çıkarıyor, gövde metni yok. Bu yüzden burada sadece alıcı
/// numarasıyla native SMS uygulaması dolu şekilde açılıyor (sms: URI),
/// mesaj metni kullanıcının kendi girişine bırakılıyor. Sesli komutla mesaj
/// içeriğini de almak (çok parçalı komut akışı) ayrı bir görev olarak
/// patika_app/TODO.md'de not edildi.
class MessageHandler {
  final ContactResolver _contacts;

  MessageHandler({ContactResolver? contacts})
      : _contacts = contacts ?? ContactResolver();

  Future<ActionResult> handle(String? entity) async {
    if (entity == null) {
      return ActionResult.fail(Tr.messageNoTarget);
    }

    // Takma ad, Türkçe ek atma ve bulanık eşleştirme (bkz. ContactMatcher).
    final (contact, failure) = await lookupContact(_contacts, entity);
    if (contact == null) return failure!;
    if (contact.phones.isEmpty) {
      return ActionResult.fail(Tr.contactNoNumber(contact.displayName));
    }

    final number = contact.phones.first;
    final uri = Uri(scheme: 'sms', path: number);
    final launched = await launchUrl(uri);
    if (!launched) {
      return ActionResult.fail(Tr.smsFailed);
    }
    return ActionResult.ok(Tr.smsOpened(contact.displayName),
        detail: Tr.smsOpenedDetail);
  }
}
