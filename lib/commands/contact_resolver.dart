import 'package:flutter_contacts/flutter_contacts.dart';

/// ARA/MESAJ niyetlerindeki `entity` (örn. "Emre") bir kişi ADI - gerçek bir
/// arama/mesaj için numaraya çözülmesi gerekiyor. Python tarafındaki
/// intent_classifier/gemini_classifier sadece ismi çıkarıyor, numara
/// bilgisi yok (bkz. patika/NOTES.md - companion app inceleme notları).
class ContactResolver {
  /// READ_CONTACTS izni isteyip verilmediyse false döner. `PermissionStatus.limited`
  /// (iOS 18+ "sadece seçili kişiler") de yeterli sayılıyor - kısmi erişimle bile
  /// isim aramak mantıklı.
  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }

  /// İsme göre rehberde arama yapar (native filter zaten kısmi/case-insensitive
  /// eşleştiriyor - bkz. ContactFilter.name). Birden fazla eşleşme varsa
  /// ilkini döner; hangi kişinin kastedildiği belirsizse (aynı isimde birden
  /// fazla kişi) bunu ayırt etmek şimdilik kapsam dışı (bkz. patika_app/TODO.md).
  Future<Contact?> findByName(String name) async {
    final granted = await requestPermission();
    if (!granted) return null;

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
      filter: ContactFilter.name(name.trim()),
    );

    return contacts.isEmpty ? null : contacts.first;
  }
}
