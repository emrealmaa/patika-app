import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/main.dart';

void main() {
  testWidgets('Uygulama açılır, iki sekme (Bağlantı/Test Modu) görünür',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PatikaApp());
    await tester.pump();

    expect(find.text('Bağlantı'), findsOneWidget);
    expect(find.text('Test Modu'), findsOneWidget);
    expect(find.text('Simülasyon modu'), findsOneWidget);
  });

  testWidgets('Test modunda sahte komut gönderilince log listeye eklenir',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PatikaApp());
    await tester.pump();

    await tester.tap(find.text('Test Modu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Komutu gönder'));
    await tester.pumpAndSettle();

    // Varsayılan seçili niyet ARA, entity boş bırakıldığı için handler
    // "Kimi arayacağımı anlayamadım" ile başarısız sonuç döner - komutun
    // gerçekten router'a ulaşıp işlendiğinin kanıtı bu log satırı. Geçmiş,
    // geri bildirim test bölümünün altında - görünene kadar kaydırılıyor.
    final logLine = find.textContaining('Kimi arayacağımı anlayamadım');
    await tester.scrollUntilVisible(logLine, 300,
        scrollable: find.byType(Scrollable).first);
    expect(logLine, findsOneWidget);
  });
}
