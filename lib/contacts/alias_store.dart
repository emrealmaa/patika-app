import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_matcher.dart';
import 'fuzzy.dart';

/// Kullanıcının sesle tanımladığı takma adlar ("annem" -> Fatma Yılmaz).
/// Yalnızca telefonda saklanır. Anahtarlar [normalizeName] ile
/// normalleştirilmiş takma addır ("Annem", "annem" ve "ANNEM" aynı kayıt).
abstract class AliasStore {
  Future<Map<String, AliasTarget>> readAll();
  Future<void> save(String alias, AliasTarget target);

  /// Silindiyse true.
  Future<bool> remove(String alias);
}

class MemoryAliasStore implements AliasStore {
  final Map<String, AliasTarget> _aliases;

  MemoryAliasStore([Map<String, AliasTarget>? initial])
      : _aliases = {for (final e in (initial ?? {}).entries) normalizeName(e.key): e.value};

  @override
  Future<Map<String, AliasTarget>> readAll() async => Map.of(_aliases);

  @override
  Future<void> save(String alias, AliasTarget target) async =>
      _aliases[normalizeName(alias)] = target;

  @override
  Future<bool> remove(String alias) async => _aliases.remove(normalizeName(alias)) != null;
}

class SharedPrefsAliasStore implements AliasStore {
  static const _key = 'patika.aliases.v1';
  // İlk kullanımda oluşturuluyor (plugin yokken yapıcı hata fırlatıyor).
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<Map<String, AliasTarget>> readAll() async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null) return {};
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          if (e.value is Map<String, dynamic>)
            e.key: AliasTarget(
              (e.value as Map<String, dynamic>)['id'] as String? ?? '',
              (e.value as Map<String, dynamic>)['name'] as String? ?? '',
            ),
      };
    } catch (e) {
      // Bozuk kayıt uygulamayı durdurmasın; takma adsız devam edilir.
      debugPrint('[Aliases] okunamadı: $e');
      return {};
    }
  }

  Future<void> _writeAll(Map<String, AliasTarget> aliases) async {
    try {
      await _prefs.setString(_key, jsonEncode({
        for (final e in aliases.entries)
          e.key: {'id': e.value.contactId, 'name': e.value.displayName},
      }));
    } catch (e) {
      debugPrint('[Aliases] kaydedilemedi: $e');
    }
  }

  @override
  Future<void> save(String alias, AliasTarget target) async {
    final all = await readAll();
    all[normalizeName(alias)] = target;
    await _writeAll(all);
  }

  @override
  Future<bool> remove(String alias) async {
    final all = await readAll();
    final removed = all.remove(normalizeName(alias)) != null;
    if (removed) await _writeAll(all);
    return removed;
  }
}
