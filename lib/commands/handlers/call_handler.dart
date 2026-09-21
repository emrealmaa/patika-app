import 'package:url_launcher/url_launcher.dart';

import '../action_result.dart';
import '../contact_resolver.dart';

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
      return ActionResult.fail('ARA: kimin aranacağı belirtilmedi');
    }

    final contact = await _contacts.findByName(entity);
    if (contact == null) {
      return ActionResult.fail(
          'ARA: "$entity" rehberde bulunamadı (izin verilmemiş olabilir)');
    }
    final phones = contact.phones;
    if (phones.isEmpty) {
      return ActionResult.fail(
          'ARA: ${contact.displayName} için kayıtlı numara yok');
    }

    final number = phones.first.number;
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri);
    if (!launched) {
      return ActionResult.fail('ARA: arama uygulaması açılamadı');
    }
    return ActionResult.ok('${contact.displayName} aranıyor ($number)');
  }
}
