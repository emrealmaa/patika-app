import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/l10n/strings_tr.dart';
import 'package:patika_app/theme/app_theme.dart';
import 'package:patika_app/widgets/anahtar_satiri.dart';
import 'package:patika_app/widgets/durum_hapi.dart';
import 'package:patika_app/widgets/kisa_ozet_kart.dart';
import 'package:patika_app/widgets/liste_satiri.dart';
import 'package:patika_app/widgets/mikrofon_hero.dart';
import 'package:patika_app/widgets/patika_card.dart';

import 'test_harness.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
    );

SemanticsData _data(WidgetTester tester, Finder f) => tester.getSemantics(f).getSemanticsData();

void main() {
  group('PatikaCard', () {
    testWidgets('içeriğini gösterir; hero süsleri TalkBack\'e girmez', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const Column(children: [
        PatikaCard(child: Text('kart içi')),
        PatikaCard.hero(child: Text('hero içi')),
      ])));
      expect(find.text('kart içi'), findsOneWidget);
      expect(find.text('hero içi'), findsOneWidget);
      expect(find.byType(HeroDecorations), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(HeroDecorations), matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      semantics.dispose();
    });
  });

  group('DurumHapi', () {
    testWidgets('anlam yazıda: TalkBack yalnızca yazıyı okur', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const DurumHapi.basari('Gözlük bağlı')));
      expect(find.bySemanticsLabel('Gözlük bağlı'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('ayrı okunuş verilebilir ("yüzde 78")', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const DurumHapi.notr('%78', semanticLabel: 'yüzde 78')));
      expect(find.bySemanticsLabel('yüzde 78'), findsOneWidget);
      expect(find.bySemanticsLabel('%78'), findsNothing);
      semantics.dispose();
    });

    test('yazı renkleri tokenlardan (AAA ölçülen çiftler)', () {
      expect(const DurumHapi.basari('x').textColor, PatikaTokens.successText);
      expect(const DurumHapi.notr('x').textColor, PatikaTokens.textSecondary);
      expect(const DurumHapi.uyari('x').textColor, PatikaTokens.sos);
    });
  });

  group('ListeSatiri', () {
    testWidgets('tek parça okunur, en az 56 dp; dokunulursa düğme ve tetiklenir',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_host(ListeSatiri(
        icon: Icons.person,
        title: 'Acil kişiler',
        subtitle: '2 kişi kayıtlı',
        onTap: () => taps++,
      )));
      final row = find.bySemanticsLabel('Acil kişiler, 2 kişi kayıtlı');
      expect(row, findsOneWidget);
      final data = _data(tester, row);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(find.byType(ListeSatiri)).height,
          greaterThanOrEqualTo(PatikaTokens.minTouch));

      tester.semantics.tap(find.semantics.byLabel('Acil kişiler, 2 kişi kayıtlı'));
      await tester.pump();
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('dokunulamayan satır düğme değil; değerin okunuşu ayrı', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const ListeSatiri(
        title: 'Gözlük pili',
        value: '%78',
        semanticLabel: 'Gözlük pili, yüzde 78',
      )));
      final data = _data(tester, find.bySemanticsLabel('Gözlük pili, yüzde 78'));
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });
  });

  group('AnahtarSatiri', () {
    testWidgets('toggled durumu bildirir, satıra dokununca değişir, en az 56 dp',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => _host(AnahtarSatiri(
          icon: Icons.volume_up,
          title: 'Bildirimleri sustur',
          value: value,
          onChanged: (v) => setState(() => value = v),
        )),
      ));
      Finder node() => find.bySemanticsLabel(RegExp('Bildirimleri sustur'));
      expect(tester.getSemantics(node()),
          isSemantics(hasToggledState: true, isToggled: false, hasTapAction: true));
      expect(tester.getSize(find.byType(AnahtarSatiri)).height,
          greaterThanOrEqualTo(PatikaTokens.minTouch));

      await tester.tap(find.text('Bildirimleri sustur'));
      await tester.pump();
      expect(value, isTrue);
      expect(tester.getSemantics(node()),
          isSemantics(hasToggledState: true, isToggled: true));
      semantics.dispose();
    });
  });

  group('KisaOzetKart', () {
    Widget kart() => _host(const KisaOzetKart(
          title: 'SOS nasıl çalışır?',
          summary: '7 saniye geri sayar; iptal etmezseniz mesaj gider.',
          details: ['"dur" iptal etmez.', 'İptal için "iptal" deyin.'],
        ));

    testWidgets('önce yalnızca özet; ayrıntı düğmeyle açılır ve kapanır', (tester) async {
      await tester.pumpWidget(kart());
      expect(find.text('7 saniye geri sayar; iptal etmezseniz mesaj gider.'), findsOneWidget);
      expect(find.text('"dur" iptal etmez.'), findsNothing);

      await tester.tap(find.text(Tr.detailShow));
      await tester.pump();
      expect(find.text('"dur" iptal etmez.'), findsOneWidget);
      expect(find.text(Tr.detailHide), findsOneWidget);

      await tester.tap(find.text(Tr.detailHide));
      await tester.pump();
      expect(find.text('"dur" iptal etmez.'), findsNothing);
    });

    testWidgets('düğme genişletildi/daraltıldı durumunu ve kartın adını bildirir',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(kart());
      final button = find.byType(TextButton);

      expect(
        tester.getSemantics(button),
        isSemantics(
          label: 'Ayrıntıyı göster: SOS nasıl çalışır?',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(PatikaTokens.minTouchSecondary));

      tester.semantics.tap(find.semantics.byLabel('Ayrıntıyı göster: SOS nasıl çalışır?'));
      await tester.pump();
      expect(
        tester.getSemantics(button),
        isSemantics(
          label: 'Ayrıntıyı gizle: SOS nasıl çalışır?',
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('TalkBack sırası: başlık, özet, düğme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(kart());
      final title = tester.getRect(find.text('SOS nasıl çalışır?'));
      final summary =
          tester.getRect(find.text('7 saniye geri sayar; iptal etmezseniz mesaj gider.'));
      final button = tester.getRect(find.byType(TextButton));
      expect(title.top, lessThan(summary.top));
      expect(summary.top, lessThan(button.top));
      semantics.dispose();
    });
  });

  group('MikrofonHero', () {
    testWidgets('etiket düğmenin içinde: tek düğüm, dokunma eylemi var, dinlemeyi başlatır',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(MikrofonHero(controller: h.app.voice)));

      final button = find.byType(ElevatedButton);
      final data = _data(tester, button);
      expect(data.label, Tr.voiceButtonLabel);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.byKey(const ValueKey('mikrofon-halkalari')), findsNothing);

      await tester.tap(button);
      await tester.pump(const Duration(seconds: 1));
      expect(h.speech.listening, isTrue);
      expect(_data(tester, button).label, Tr.voiceListeningLabel);

      // Dinlerken halkalar var ama TalkBack'e girmiyor.
      final rings = find.byKey(const ValueKey('mikrofon-halkalari'));
      expect(rings, findsOneWidget);
      expect(tester.widget(rings), isA<ExcludeSemantics>());
      semantics.dispose();
    });
  });
}
