import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sos_config.dart';

/// Acil durumda mesaj atılacak / aranacak kişi. Numara **kopyası** saklanır:
/// kişi rehberden silinse ya da değişse de SOS çalışsın.
class EmergencyContact {
  final String name;
  final String number;

  const EmergencyContact(this.name, this.number);

  /// Aynı numara farklı yazılışlarla ("0532 111 22 33", "+90 532 111 22 33")
  /// aynı kişi sayılsın diye son 10 rakam.
  String get key {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Map<String, String> toJson() => {'name': name, 'number': number};

  static EmergencyContact? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final number = json['number'];
    if (name is! String || number is! String || number.trim().isEmpty) return null;
    return EmergencyContact(name, number);
  }

  @override
  bool operator ==(Object other) => other is EmergencyContact && other.name == name && other.number == number;

  @override
  int get hashCode => Object.hash(name, number);
}

enum EmergencyAddResult { added, duplicate, full }

/// Acil kişiler (en çok [SosConfig.maxContacts]). Yalnızca telefonda saklanır.
abstract class EmergencyContactStore {
  Future<List<EmergencyContact>> readAll();
  Future<EmergencyAddResult> add(EmergencyContact contact);

  /// [key] = [EmergencyContact.key]; silindiyse true.
  Future<bool> remove(String key);
}

/// Ekleme/silme kuralları iki uygulamada da aynı olsun diye tek yerde.
EmergencyAddResult applyAdd(List<EmergencyContact> list, EmergencyContact contact) {
  if (list.any((c) => c.key == contact.key)) return EmergencyAddResult.duplicate;
  if (list.length >= SosConfig.maxContacts) return EmergencyAddResult.full;
  list.add(contact);
  return EmergencyAddResult.added;
}

class MemoryEmergencyContactStore implements EmergencyContactStore {
  final List<EmergencyContact> _list;

  MemoryEmergencyContactStore([List<EmergencyContact>? initial]) : _list = [...?initial];

  @override
  Future<List<EmergencyContact>> readAll() async => List.of(_list);

  @override
  Future<EmergencyAddResult> add(EmergencyContact contact) async => applyAdd(_list, contact);

  @override
  Future<bool> remove(String key) async {
    final before = _list.length;
    _list.removeWhere((c) => c.key == key);
    return _list.length != before;
  }
}

/// Acil kişileri Android'in **hiçbir zaman** otomatik yedeğe (buluta ya da
/// cihazdan cihaza aktarıma) almadığı `Context.getNoBackupFilesDir()`
/// dizininde saklar - bu, Android'in bu tür veriler için dokümante ettiği
/// standart yoldur, ayrı bir yedek kuralı (XML) ya da yeni bir paket
/// gerektirmez (bkz. kanal `patika/emergency_contacts`,
/// `EmergencyContactsStorage.kt`). Diğer ayarlar (settings, takma adlar)
/// olağan `SharedPreferences` üzerinden yedeklenmeye devam eder - yalnızca
/// acil kişi listesi istisna.
///
/// **Değerlendirilen alternatif (kurulmadı):** ek olarak şifreli depolama
/// (ör. `flutter_secure_storage`, Android Keystore destekli). Artı: yerel
/// dosya bir şekilde (kök erişimi, dosya yöneticisi) okunursa da korur.
/// Eksi: cihaz kökse (root) uygulamanın kendisi de çözüp kullanabildiği için
/// şifreleme çoğu durumda ek koruma sağlamaz (anahtar süreç içinde);
/// asıl adreslenen tehdit (bulut yedeği/hesap ele geçirme) zaten
/// `noBackupFilesDir` ile kapatılıyor; ek bağımlılık ve bakım yükü. Karar:
/// şimdilik gerekmiyor, istenirse sonra eklenir (paket kurulmadan önce onay
/// gerekir).
class SecureFileEmergencyContactStore implements EmergencyContactStore {
  static const _channel = MethodChannel('patika/emergency_contacts');

  @override
  Future<List<EmergencyContact>> readAll() async {
    try {
      final raw = await _channel.invokeMethod<String>('read');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [for (final e in decoded) ?EmergencyContact.fromJson(e)];
    } catch (e) {
      // Bozuk kayıt uygulamayı durdurmasın; ama sessiz de kalmasın: kişi
      // yok gibi davranılır ve SOS bunu "acil kişi yok" diye söyler.
      debugPrint('[Emergency] kişiler okunamadı: ${e.runtimeType}');
      return [];
    }
  }

  @override
  Future<EmergencyAddResult> add(EmergencyContact contact) async {
    final list = await readAll();
    final result = applyAdd(list, contact);
    if (result == EmergencyAddResult.added) await _write(list);
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    final list = await readAll();
    final before = list.length;
    list.removeWhere((c) => c.key == key);
    if (list.length == before) return false;
    await _write(list);
    return true;
  }

  Future<void> _write(List<EmergencyContact> list) => _channel.invokeMethod<void>(
        'write',
        {'json': jsonEncode([for (final c in list) c.toJson()])},
      );
}
