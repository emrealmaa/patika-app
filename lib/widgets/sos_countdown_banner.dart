import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings_tr.dart';
import '../sos/sos_config.dart';
import '../sos/sos_controller.dart';
import '../theme/app_theme.dart';

/// Acil durum geri sayımı ve gönderimi sürerken uygulamanın TAMAMINI kaplayan
/// koyu ekran: kalan süre, geri sayım halkası ve büyük "İptal et" düğmesi
/// (telefon ekranından iptal kanalı). Boştayken hiçbir şey çizmez.
///
/// - [BlockSemantics]: ekran açıkken arkadaki sekmeler ve alt çubuk
///   TalkBack'ten düşer; kullanıcı görünmeyen öğelere gidemez. Odak iptal
///   düğmesine ZORLA taşınmaz (TalkBack geri sayım duyurusunun üstüne
///   konuşmasın).
/// - Bilgi yalnızca renkle verilmez: kalan süre cümleyle yazılır. Düğme en az
///   64 dp ve etiketi düğmenin içinde (dışarıdan `excludeSemantics` ile
///   sarılmıyor: TalkBack'te dokunma eylemi kaybolurdu).
/// - Duyuru TalkBack'e değil TTS'e gider (`FeedbackSosAnnouncer`), bu yüzden
///   canlı bölge (liveRegion) kullanılmaz; çift okuma olmaz.
/// - Halka [SosStatus.remaining]'den çizilir, kendi zamanlayıcısı yok; geri
///   sayım mantığı tamamen [SosController]'da. Halka ve büyük sayı süs
///   (cümle zaten okunuyor).
class SosCountdownBanner extends StatelessWidget {
  final SosController sos;

  const SosCountdownBanner({super.key, required this.sos});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SosStatus>(
      valueListenable: sos.status,
      builder: (context, status, _) {
        switch (status.phase) {
          case SosPhase.idle:
          case SosPhase.preparing:
            return const SizedBox.shrink();
          case SosPhase.sending:
            return const _FullScreen(
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.sms, size: 72, color: PatikaTokens.onSosBackground),
                ),
                SizedBox(height: 24),
                _Title(Tr.sosBannerSending),
              ],
            );
          case SosPhase.countdown:
            final seconds = status.remaining.inSeconds;
            return _FullScreen(
              children: [
                _Title(Tr.sosBannerTitle(seconds)),
                const SizedBox(height: 28),
                _CountdownRing(remaining: status.remaining),
                const SizedBox(height: 28),
                Text(
                  Tr.sosScreenDefaultSend,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PatikaTokens.sosWarningText,
                      ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => sos.cancel(SosCancelSource.screen),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    backgroundColor: PatikaTokens.onSosBackground,
                    foregroundColor: PatikaTokens.sosBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PatikaTokens.radiusCard),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: PatikaTokens.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text(Tr.sosCancelButton),
                ),
                const SizedBox(height: 12),
                Text(
                  Tr.sosScreenVoiceCancelHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PatikaTokens.onSosBackgroundMuted,
                      ),
                ),
              ],
            );
        }
      },
    );
  }
}

/// Koyu tam ekran zemin. Arkadaki her şeyin anlamsal ağacını kapatır ve
/// dokunuşların arkaya geçmesini engeller (opak Material).
class _FullScreen extends StatelessWidget {
  final List<Widget> children;

  const _FullScreen({required this.children});

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Material(
        color: PatikaTokens.sosBackground,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 48)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        Tr.sosScreenCaption,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: PatikaTokens.onSosBackgroundMuted,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;

  const _Title(this.text);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: PatikaTokens.onSosBackground,
            ),
      ),
    );
  }
}

/// Azalan geri sayım halkası + ortada büyük kalan saniye. Tamamı süs: aynı
/// bilgi başlık cümlesinde yazılı ve okunuyor.
class _CountdownRing extends StatelessWidget {
  static const size = 220.0;

  final Duration remaining;

  const _CountdownRing({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final total = SosConfig.manualCountdown.inMilliseconds;
    final fraction = total == 0 ? 0.0 : (remaining.inMilliseconds / total).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: Center(
        child: SizedBox(
          key: const ValueKey('sos-geri-sayim-halkasi'),
          width: size,
          height: size,
          // Yalnızca saniyelik değerler arasında yumuşatma: hedef her zaman
          // status.remaining'den; kendi zamanlayıcısı ve mantığı yok. Hareketi
          // azalt açıkken süre sıfır (ticker hiç çalışmaz, değer anında).
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(seconds: 1),
            builder: (context, value, child) => CustomPaint(
              painter: CountdownRingPainter(fraction: value),
              child: child,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${remaining.inSeconds}',
                    style: const TextStyle(
                      color: PatikaTokens.onSosBackground,
                      fontSize: 84,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Tr.sosScreenSecondsUnit,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: PatikaTokens.onSosBackgroundMuted,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Halkayı çizer: soluk iz + kalan oran kadar yay (saat 12'den saat yönünde).
class CountdownRingPainter extends CustomPainter {
  /// Kalan süre / toplam süre (0..1).
  final double fraction;

  const CountdownRingPainter({required this.fraction});

  static const strokeWidth = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = PatikaTokens.sosRingTrack;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = PatikaTokens.sosRing;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);
    if (fraction > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(CountdownRingPainter oldDelegate) => oldDelegate.fraction != fraction;
}
