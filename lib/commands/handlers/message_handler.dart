import 'package:url_launcher/url_launcher.dart';

import '../action_result.dart';
import '../contact_resolver.dart';

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
      return ActionResult.fail('MESAJ: kime gönderileceği belirtilmedi');
    }

    final contact = await _contacts.findByName(entity);
    if (contact == null) {
      return ActionResult.fail(
          'MESAJ: "$entity" rehberde bulunamadı (izin verilmemiş olabilir)');
    }
    final phones = contact.phones;
    if (phones.isEmpty) {
      return ActionResult.fail(
          'MESAJ: ${contact.displayName} için kayıtlı numara yok');
    }

    final number = phones.first.number;
    final uri = Uri(scheme: 'sms', path: number);
    final launched = await launchUrl(uri);
    if (!launched) {
      return ActionResult.fail('MESAJ: mesaj uygulaması açılamadı');
    }
    return ActionResult.ok(
        '${contact.displayName} için mesaj uygulaması açıldı ($number)');
  }
}
