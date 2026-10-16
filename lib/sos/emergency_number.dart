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

  /// `--dart-define=PATIKA_SOS_TEST_NUMBER=<kendi ikinci numaranız>`: debug
  /// derlemesinde "112 aranacak" durumunda bu numara aranır (uçtan uca deneme
  /// için). Release derlemesinde tamamen yok sayılır.
  static const _testNumberDefine = String.fromEnvironment('PATIKA_SOS_TEST_NUMBER');

  final String? _testNumber;
  final bool _release;

  /// [release] yalnÄ±zca testler iÃ§indir (varsayÄ±lan: gerÃ§ek derleme tÃ¼rÃ¼).
  const EmergencyNumber({String? debugTestNumber, bool release = kReleaseMode})
      : _release = release,
        _testNumber = (release || debugTestNumber == real) ? null : debugTestNumber;

  /// Uygulamadaki varsayılan: `dart-define` ile verilen test numarası (yoksa
  /// release dışında hiçbir şey aranmaz).
  const EmergencyNumber.fromDefines()
      : this(debugTestNumber: _testNumberDefine == '' ? null : _testNumberDefine);

  /// Aranacak numara; aranamıyorsa (release dışı ve test numarası yok) null.
  String? get dialNumber => _release ? real : _testNumber;

  bool get canDial => dialNumber != null;
}
