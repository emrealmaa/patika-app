import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patika_app/theme/app_theme.dart';

/// WCAG 2.x göreli parlaklık.
double _luminance(Color c) {
  double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG kontrast oranı (1-21).
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('kontrast (AAA)', () {
    test('formül bilinen değerleri verir', () {
      expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrast(Colors.white, Colors.white), closeTo(1, 0.001));
    });

    test('her gerçek metin/zemin çifti en az 7:1', () {
      expect(PatikaTokens.textPairs, isNotEmpty);
      final failures = <String>[];
      for (final MapEntry(key: name, value: (fg, bg)) in PatikaTokens.textPairs.entries) {
        final ratio = contrast(fg, bg);
        // Ölçüm sonucu test çıktısında görünsün (rapor için).
        // ignore: avoid_print
        print('ölçüm: $name = ${ratio.toStringAsFixed(2)}:1');
        if (ratio < 7) failures.add('$name ${ratio.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty, reason: '7:1 altında kalan çiftler');
    });

    test('anlam taşıyan grafik öğeler en az 3:1', () {
      final failures = <String>[];
      for (final MapEntry(key: name, value: (fg, bg)) in PatikaTokens.graphicPairs.entries) {
        final ratio = contrast(fg, bg);
        // ignore: avoid_print
        print('ölçüm (grafik): $name = ${ratio.toStringAsFixed(2)}:1');
        if (ratio < 3) failures.add('$name ${ratio.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty);
    });
  });

  test('tema Plus Jakarta Sans kullanır ve pubspec onu tanıtır', () {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, PatikaTokens.fontFamily);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${PatikaTokens.fontFamily}'));
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      expect(File('assets/fonts/PlusJakartaSans-$w.ttf').existsSync(), isTrue, reason: w);
    }
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
  });

  // Tüm renkler tek tema dosyasında: ekranlar ve widget'lar sabit renk
  // yazmaz (Colors.transparent hariç - renk değil, "renk yok").
  test('ekran ve widget dosyalarında sabit renk yok', () {
    final offenders = <String>[];
    final pattern = RegExp(r'Color\(0x|Colors\.(?!transparent\b)\w+|Color\.from');
    for (final dir in ['lib/screens', 'lib/widgets', 'lib/main.dart']) {
      final entities = FileSystemEntity.isFileSync(dir)
          ? [File(dir)]
          : Directory(dir).listSync(recursive: true).whereType<File>();
      for (final f in entities.where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
