import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/commands/contact_resolver.dart';
import 'package:patika_app/commands/handlers/alias_handler.dart';
import 'package:patika_app/commands/handlers/number_handler.dart';
import 'package:patika_app/commands/intent.dart';
import 'package:patika_app/commands/voice_intent_classifier.dart';
import 'package:patika_app/contacts/alias_store.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/contacts/fuzzy.dart';
import 'package:patika_app/contacts/turkish_stemmer.dart';

/// Bilerek zor durumlar içeren sahte rehber: iki Ahmet, Ali/Alp, "Annem"
/// adlı bir kayıt, iki Yılmaz.
const _contacts = [
  ContactEntry('1', 'Ahmet Yılmaz', ['0555 000 00 01']),
  ContactEntry('2', 'Ahmet Kaya', ['0555 000 00 02']),
  ContactEntry('3', 'Ayşe Demir', ['0555 000 00 03']),
  ContactEntry('4', 'Ali Veli', ['0555 000 00 05']),
  ContactEntry('5', 'Alp Er', ['0555 000 00 06']),
  ContactEntry('6', 'Annem', ['0555 000 00 04']),
  ContactEntry('7', 'Mehmet Öz', ['+90 555 000 00 09']),
  ContactEntry('8', 'Fatma Yılmaz', ['0555 000 00 07']),
  ContactEntry('9', 'Emre Can', ['0555 000 00 08']),
];

class _FakeSource implements ContactSource {
  int loads = 0;

  @override
  Future<List<ContactEntry>> loadAll() async {
    loads++;
    return _contacts;
  }
}

void main() {
  const matcher = ContactMatcher();

  String? found(ContactMatch m) => m is ContactFound ? m.contact.displayName : null;
  List<String>? ambiguous(ContactMatch m) =>
      m is ContactAmbiguous ? [for (final c in m.candidates) c.displayName] : null;

  group('kök adayları', () {
    test('iyelik + belirtme: annemi -> annem -> anne', () {
      final roots = rootCandidates('annemi');
      expect(roots.first, 'annemi');
      expect(roots, containsAll(['annem', 'anne']));
    });

    test('orijinal biçim her zaman ilk aday: Ali -> [ali, al]', () {
      expect(rootCandidates('Ali').first, 'ali');
    });

    test('kesme işareti: sonrası kesinlikle ek, tek aday', () {
      expect(rootCandidates("Mehmet'in"), ['mehmet']);
      expect(rootCandidates("Ahmet Yılmaz'ı"), ['ahmet yılmaz']);
      expect(rootCandidates('Ayşe’ye'), ['ayşe']);
    });

    test('sevgi eki: anneciğim -> anne (tek katman)', () {
      final roots = rootCandidatesWithDepth('anneciğim');
      expect(roots, contains(('anne', 1)));
    });

    test('Türkçe büyük İ', () => expect(rootCandidates('İsmail').first, 'ismail'));
  });

  group('bulanık eşleştirme', () {
    test('normalleştirme Türkçe karakterleri sadeleştirir', () {
      expect(normalizeName('Ayşe Öztürk'), 'ayse ozturk');
      expect(normalizeName("  İSMAİL   Çağlar "), 'ismail caglar');
    });

    test('Jaro-Winkler', () {
      expect(jaroWinkler('mehmet', 'mehmet'), 1);
      expect(jaroWinkler('mehmet', 'mehmed'), greaterThan(0.9));
      expect(jaroWinkler('mehmet', 'ahmet'), lessThan(ContactMatcher.threshold));
    });
  });

  group('eşleştirici', () {
    ContactMatch m(String spoken, [Map<String, AliasTarget> aliases = const {}]) =>
        matcher.match(spoken, _contacts, aliases: aliases);

    test('iyelik + belirtme eki: "annemi" -> Annem', () => expect(found(m('annemi')), 'Annem'));
    test('yönelme eki: "Ayşe\'ye" -> Ayşe Demir', () => expect(found(m("Ayşe'ye")), 'Ayşe Demir'));
    test('tamlayan eki: "Mehmet\'in" -> Mehmet Öz', () => expect(found(m("Mehmet'in")), 'Mehmet Öz'));
    test('kesmesiz tamlayan: "Mehmetin" -> Mehmet Öz', () => expect(found(m('Mehmetin')), 'Mehmet Öz'));
    test('Türkçe karakter varyasyonu: "Ayse" -> Ayşe Demir',
        () => expect(found(m('Ayse')), 'Ayşe Demir'));
    test('tanıma hatası: "Mehmed" -> Mehmet Öz', () => expect(found(m('Mehmed')), 'Mehmet Öz'));
    test('"Ali" Ali Veli olur, "Al" + Alp Er değil', () => expect(found(m('Ali')), 'Ali Veli'));
    test('tam ad: "Ahmet Yılmaz\'ı" -> Ahmet Yılmaz',
        () => expect(found(m("Ahmet Yılmaz'ı")), 'Ahmet Yılmaz'));

    test('iki Ahmet: belirsiz, ikisi de aday', () {
      expect(ambiguous(m('Ahmet')), unorderedEquals(['Ahmet Yılmaz', 'Ahmet Kaya']));
    });

    test('soyadıyla: "Yılmaz" iki kişiye uyar', () {
      expect(ambiguous(m('Yılmaz')), unorderedEquals(['Ahmet Yılmaz', 'Fatma Yılmaz']));
    });

    test('rehberde yok', () => expect(m('Zeynep'), isA<ContactNotFound>()));

    test('takma ad rehberden önce gelir: "annemi" -> Fatma Yılmaz', () {
      final r = m('annemi', {'annem': const AliasTarget('8', 'Fatma Yılmaz')});
      expect(found(r), 'Fatma Yılmaz');
      expect((r as ContactFound).viaAlias, isTrue);
    });

    test('takma adın kişisi silinip yeniden eklendiyse (kimlik değişti) adla bulunur', () {
      final r = m('annem', {'annem': const AliasTarget('eski-id', 'Fatma Yılmaz')});
      expect(found(r), 'Fatma Yılmaz');
    });
  });

  group('ContactResolver', () {
    test('izin yoksa rehber okunmaz', () async {
      final source = _FakeSource();
      final resolver = ContactResolver(source: source, ensurePermission: () async => false);
      expect(await resolver.resolve('Ahmet'), isA<ContactPermissionDenied>());
      expect(source.loads, 0);
    });

    test('rehber 60 sn önbellekte tutulur, sonra yeniden okunur', () async {
      final source = _FakeSource();
      var now = DateTime(2026, 9, 26, 12);
      final resolver = ContactResolver(
        source: source,
        ensurePermission: () async => true,
        now: () => now,
      );
      await resolver.resolve('Ayşe');
      await resolver.resolve('Emre');
      expect(source.loads, 1);
      now = now.add(const Duration(seconds: 61));
      await resolver.resolve('Emre');
      expect(source.loads, 2);
    });
  });

  group('tarifteki örnekler (sınıflandırıcı + eşleştirici)', () {
    late ContactResolver resolver;
    setUp(() => resolver = ContactResolver(source: _FakeSource(), ensurePermission: () async => true));

    test('"Annemi ara" -> Annem', () async {
      final cmd = classifyVoiceCommand('Annemi ara');
      expect(cmd.intent, PatikaIntent.ara);
      expect(found(await resolver.resolve(cmd.entity!)), 'Annem');
    });

    test('"Ayşe\'ye mesaj at" -> Ayşe Demir', () async {
      final cmd = classifyVoiceCommand("Ayşe'ye mesaj at");
      expect(cmd.intent, PatikaIntent.mesaj);
      expect(found(await resolver.resolve(cmd.entity!)), 'Ayşe Demir');
    });

    test('"Mehmet\'in numarasını söyle" -> numara rakam rakam okunur', () async {
      final cmd = classifyVoiceCommand("Mehmet'in numarasını söyle");
      expect(cmd.intent, PatikaIntent.numara);
      expect(cmd.entity, 'Mehmet');
      final result = await NumberHandler(contacts: resolver).handle(cmd.entity);
      expect(result.message, 'Mehmet Öz: artı 9 0, 5 5 5, 0 0 0, 0 0, 0 9');
    });

    test('"Ayse\'yi ara" (Türkçe karaktersiz) -> Ayşe Demir', () async {
      final cmd = classifyVoiceCommand("Ayse'yi ara");
      expect(found(await resolver.resolve(cmd.entity!)), 'Ayşe Demir');
    });

    test('belirsizlikte adaylar okunup tam ad istenir', () async {
      final result = await NumberHandler(contacts: resolver).handle('Ahmet');
      expect(result.success, isFalse);
      expect(result.message, startsWith('2 kişi buldum'));
      expect(result.message, contains('Ahmet Yılmaz'));
      expect(result.message, contains('Ahmet Kaya'));
    });
  });

  group('numara okuma', () {
    test('rakamlar gruplanır, TTS tek tek okur', () {
      expect(NumberHandler.spokenDigits('0555 000 00 09'), '0 5 5 5, 0 0 0, 0 0, 0 9');
      expect(NumberHandler.spokenDigits('05550000009'), '0 5 5 5, 0 0 0, 0 0, 0 9');
      expect(NumberHandler.spokenDigits('+90 555 000 00 09'), 'artı 9 0, 5 5 5, 0 0 0, 0 0, 0 9');
      expect(NumberHandler.spokenDigits('112'), '1 1 2');
    });
  });

  group('takma adlar', () {
    late MemoryAliasStore aliases;
    late AliasHandler handler;
    late ContactResolver resolver;

    setUp(() {
      aliases = MemoryAliasStore();
      resolver = ContactResolver(
        source: _FakeSource(),
        aliases: aliases,
        ensurePermission: () async => true,
      );
      handler = AliasHandler(contacts: resolver);
    });

    Future<void> say(String text) async {
      final cmd = classifyVoiceCommand(text);
      expect(cmd.intent, PatikaIntent.takmaAd, reason: text);
      await handler.handle(cmd.entity);
    }

    test('"annemi Fatma Yılmaz olarak kaydet"', () async {
      await say('annemi Fatma Yılmaz olarak kaydet');
      expect((await aliases.readAll())['annem']?.displayName, 'Fatma Yılmaz');
      // Rehberde "Annem" adlı biri olsa da takma ad önce gelir.
      expect(found(await resolver.resolve('annemi')), 'Fatma Yılmaz');
    });

    test('ters sıra: "Fatma Yılmaz\'ı annem olarak kaydet"', () async {
      await say("Fatma Yılmaz'ı annem olarak kaydet");
      expect((await aliases.readAll())['annem']?.displayName, 'Fatma Yılmaz');
    });

    test('okuma ve silme', () async {
      await say('babamı Ali Veli olarak kaydet');
      final list = await handler.handle(classifyVoiceCommand('takma adları oku').entity);
      expect(list.message, contains('babam, Ali Veli'));

      final removed = await handler.handle(classifyVoiceCommand('babam takma adını sil').entity);
      expect(removed.success, isTrue);
      expect(await aliases.readAll(), isEmpty);
    });

    test('rehberde olmayan kişiye takma ad verilmez', () async {
      final cmd = classifyVoiceCommand('patronumu Zeynep Ak olarak kaydet');
      final result = await handler.handle(cmd.entity);
      expect(result.success, isFalse);
      expect(await aliases.readAll(), isEmpty);
    });
  });
}
