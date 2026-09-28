import 'package:flutter/foundation.dart';

/// Aranacak acil çağrı numarası. **Gerçek 112'nin kodda geçtiği tek yer
/// burasıdır** (bir test bunu kilitler).
///
/// - Release derlemesinde numara sabit 112'dir ve değiştirilemez.
/// - Release DIŞINDA (debug, profile, `flutter test`) gerçek 112 hiçbir
///   yolla aranmaz: numara yalnızca enjekte edilen bir test numarasıdır,
///   verilmemişse null (arama reddedilir). Test numarası olarak "112"
///   verilse bile yok sayılır.
///
/// Neden: asılsız 112 ihbarına idari para cezası uygulanıyor (5326 md. 42/A,
/// bkz. CLAUDE.md Faz 7 kararları) ve geliştirme sırasında yanlışlıkla
/// gerçek 112 aranmamalı.
class EmergencyNumber {
  static const real = '112';

  final String? _testNumber;

  const EmergencyNumber({String? debugTestNumber})
      : _testNumber = (kReleaseMode || debugTestNumber == real) ? null : debugTestNumber;

  /// Aranacak numara; aranamıyorsa (release dışı ve test numarası yok) null.
  String? get dialNumber => kReleaseMode ? real : _testNumber;

  bool get canDial => dialNumber != null;
}
