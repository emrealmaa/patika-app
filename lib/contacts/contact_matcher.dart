import 'package:flutter/foundation.dart';

import 'fuzzy.dart';
import 'turkish_stemmer.dart';

/// Rehberdeki bir kişi - eşleştirmenin ihtiyaç duyduğu kadarı. Numarası
/// olmayan kişiler kaynakta zaten eleniyor (arama/mesaj/numara için işe
/// yaramazlar).
class ContactEntry {
  final String id;
  final String displayName;
  final List<String> phones;

  const ContactEntry(this.id, this.displayName, this.phones);

  @override
  String toString() => displayName;
}

/// Takma adın bağlı olduğu kişi ("annem" -> Fatma Yılmaz).
class AliasTarget {
  final String contactId;
  final String displayName;

  const AliasTarget(this.contactId, this.displayName);
}

sealed class ContactMatch {
  const ContactMatch();
}

class ContactFound extends ContactMatch {
  final ContactEntry contact;
  final bool viaAlias;
  const ContactFound(this.contact, {this.viaAlias = false});
}

/// Birden fazla kişi neredeyse aynı puanla eşleşti ("iki Ahmet var") -
/// Faz 3b'de "hangisi?" diye sorulacak. En iyi eşleşme önde.
class ContactAmbiguous extends ContactMatch {
  final List<ContactEntry> candidates;
  const ContactAmbiguous(this.candidates);
}

class ContactNotFound extends ContactMatch {
  const ContactNotFound();
}

class ContactPermissionDenied extends ContactMatch {
  const ContactPermissionDenied();
}

/// Söylenen adı rehberle eşleştirir: önce takma adlar, sonra rehber.
///
/// Söylenen adın her kök adayı ([rootCandidates]) her kişinin tam adıyla ve
/// ad/soyad parçalarıyla Jaro-Winkler ile karşılaştırılır:
/// - Tam ad: puan olduğu gibi. Adın ilk parçası ("Ahmet" -> Ahmet Yılmaz):
///   küçük ceza. Diğer parçalar ("Yılmaz'ı ara"): biraz daha büyük ceza.
/// - Ek atılarak elde edilen aday her katman için küçük ceza alır: "Ali"
///   rehberde varsa her zaman "Al"ı geçer.
/// - En iyi puan [threshold] altındaysa bulunamadı; en iyiye [ambiguityGap]
///   kadar yakın başka kişiler varsa belirsiz.
class ContactMatcher {
  static const threshold = 0.88;
  static const ambiguityGap = 0.03;
  static const maxCandidates = 3;

  static const _firstTokenFactor = 0.99;
  static const _otherTokenFactor = 0.96;
  static const _perStripFactor = 0.985;

  const ContactMatcher();

  ContactMatch match(
    String spoken,
    List<ContactEntry> contacts, {
    Map<String, AliasTarget> aliases = const {},
  }) {
    final roots = rootCandidatesWithDepth(spoken);
    if (roots.isEmpty) return const ContactNotFound();

    // 1) Takma adlar: herhangi bir kök adayı kayıtlı bir takma adsa.
    for (final (root, _) in roots) {
      final target = aliases[normalizeName(root)];
      if (target == null) continue;
      final byId = contacts.where((c) => c.id == target.contactId);
      if (byId.isNotEmpty) return ContactFound(byId.first, viaAlias: true);
      // Kişi silinmiş/kimliği değişmiş olabilir: kayıtlı adla dene.
      final byName = contacts.where(
          (c) => normalizeName(c.displayName) == normalizeName(target.displayName));
      if (byName.isNotEmpty) return ContactFound(byName.first, viaAlias: true);
    }

    // 2) Rehber: her kişi için en iyi puan.
    final normalizedRoots = [
      for (final (root, depth) in roots)
        (normalizeName(root), _pow(_perStripFactor, depth)),
    ];
    final scored = <(ContactEntry, double)>[];
    final all = kDebugMode ? <(ContactEntry, double)>[] : null;
    for (final contact in contacts) {
      final full = normalizeName(contact.displayName);
      if (full.isEmpty) continue;
      final parts = full.split(' ');
      var best = 0.0;
      for (final (root, penalty) in normalizedRoots) {
        var s = jaroWinkler(root, full);
        if (!root.contains(' ')) {
          for (var p = 0; p < parts.length; p++) {
            final factor = p == 0 ? _firstTokenFactor : _otherTokenFactor;
            final partScore = jaroWinkler(root, parts[p]) * factor;
            if (partScore > s) s = partScore;
          }
        }
        s *= penalty;
        if (s > best) best = s;
      }
      all?.add((contact, best));
      // Eşiğin hemen altındakiler de tutulur: "bulundu" için en iyinin eşiği
      // geçmesi gerekir, ama belirsizlik kontrolü yakın adayları da hesaba
      // katar (aşağıda).
      if (best >= threshold - ambiguityGap) scored.add((contact, best));
    }
    if (all != null) {
      // Eşik ayarı için: eşik altı adaylar dahil en iyi 3 (yalnızca debug;
      // rehber adları bu cihazın logunda kalır).
      all.sort((a, b) => b.$2.compareTo(a.$2));
      debugPrint('[Contacts] "$spoken" -> ${all.take(3).map((e) => '${e.$1.displayName}:${e.$2.toStringAsFixed(3)}').join(', ')} '
          '(eşik $threshold)');
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty || scored.first.$2 < threshold) return const ContactNotFound();

    // Belirsizlik: en iyiye [ambiguityGap] kadar yakın başka biri varsa -
    // eşiğin binde birlik farkla altında kalsa bile. Gerçek cihazda
    // "Ayyıldız" -> Koray Yıldız 0,889 / Kaan Yıldız 0,880: ikinci eşiğin
    // hemen altında kaldığı için soru sorulmadan biri SEÇİLİYORDU (yanlış
    // kişiyi arama riski). Artık "hangisi?" diye sorulur.
    final top = scored.first.$2;
    final close = [
      for (final (c, s) in scored)
        if (top - s <= ambiguityGap) c,
    ];
    if (close.length == 1) return ContactFound(close.single);
    return ContactAmbiguous(close.take(maxCandidates).toList());
  }

  /// Atılan her ek katmanı için ceza çarpanı (0 katman: 1).
  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
