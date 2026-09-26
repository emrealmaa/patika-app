import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../contacts/alias_store.dart';
import '../contacts/contact_matcher.dart';

/// Rehber soyutlaması - testlerde sahte bir liste veriliyor.
abstract class ContactSource {
  /// Numarası olan tüm kişiler (numarasız kişiler arama/mesaj/numara için
  /// işe yaramaz, eşleştirmeye hiç girmez).
  Future<List<ContactEntry>> loadAll();
}

class FlutterContactsSource implements ContactSource {
  @override
  Future<List<ContactEntry>> loadAll() async {
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
    return [
      for (final c in contacts)
        if (c.phones.isNotEmpty && (c.displayName ?? '').trim().isNotEmpty)
          ContactEntry(c.id ?? '', c.displayName!.trim(), [
            for (final p in c.phones) p.number,
          ]),
    ];
  }
}

/// ARA/MESAJ/NUMARA niyetlerindeki `entity` (örn. "annemi", "Mehmet'in")
/// bir kişi ADI - numaraya çözülmesi gerekiyor. Takma adlar, Türkçe ek
/// atma ve bulanık eşleştirme [ContactMatcher]'da; burada rehberin
/// okunması, izin ve kısa süreli önbellek var.
class ContactResolver {
  /// Rehber bu kadar süre önbellekte tutulur - her komutta binlerce kişiyi
  /// yeniden okumamak için; yeni eklenen kişi en geç bu süre sonra görünür.
  static const cacheFor = Duration(seconds: 60);

  final ContactSource _source;
  final AliasStore aliases;
  final Future<bool> Function() _ensurePermission;
  final ContactMatcher _matcher;
  final DateTime Function() _now;

  List<ContactEntry>? _cache;
  DateTime? _cachedAt;

  ContactResolver({
    ContactSource? source,
    AliasStore? aliases,
    Future<bool> Function()? ensurePermission,
    ContactMatcher matcher = const ContactMatcher(),
    DateTime Function()? now,
  })  : _source = source ?? FlutterContactsSource(),
        aliases = aliases ?? MemoryAliasStore(),
        _ensurePermission = ensurePermission ?? _defaultPermission,
        _matcher = matcher,
        _now = now ?? DateTime.now;

  /// Sesli açıklama olmadan (eski davranış) - AppState açıklamalı sürümü
  /// veriyor (PermissionExplainer). `limited` (iOS "seçili kişiler") de
  /// yeterli sayılıyor.
  static Future<bool> _defaultPermission() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }

  /// Söylenen adı bir kişiye çözer (önce takma adlar, sonra rehber).
  Future<ContactMatch> resolve(String spokenName) async {
    final contacts = await _contacts();
    if (contacts == null) return const ContactPermissionDenied();
    return _matcher.match(spokenName, contacts, aliases: await aliases.readAll());
  }

  /// Takma ad kaydında: söylenen kişi adı rehberde kime karşılık geliyor
  /// (takma adlara bakmadan).
  Future<ContactMatch> resolveInContacts(String spokenName) async {
    final contacts = await _contacts();
    if (contacts == null) return const ContactPermissionDenied();
    return _matcher.match(spokenName, contacts);
  }

  /// İzin yoksa null.
  Future<List<ContactEntry>?> _contacts() async {
    final cachedAt = _cachedAt;
    if (_cache != null && cachedAt != null && _now().difference(cachedAt) < cacheFor) {
      return _cache;
    }
    if (!await _ensurePermission()) return null;
    try {
      _cache = await _source.loadAll();
      _cachedAt = _now();
      return _cache;
    } catch (e) {
      debugPrint('[Contacts] rehber okunamadı: $e');
      rethrow;
    }
  }
}
