import 'package:flutter/material.dart';

import '../l10n/strings_tr.dart';
import '../theme/app_theme.dart';
import '../voice/voice_controller.dart';
import 'nabiz_halkalari.dart';
import 'patika_card.dart';

/// Konuş sekmesinin büyük dinleme düğmesi: gradyanlı hero kartın TAMAMI
/// tek bir [ElevatedButton]. Ortada beyaz mikrofon dairesi, dinlerken
/// çevresinde halkalar.
///
/// [VoiceButton] ile aynı sözleşme: mantık [VoiceController]'da, etiket
/// düğmenin İÇİNDE (dışarıdan `excludeSemantics` ile sarmak dokunma
/// eylemini silerdi), TalkBack ikon ve görsel metin yerine tek açıklayıcı
/// etiketi okur. Halkalar ve dekoratif daireler [ExcludeSemantics] içinde.
/// Durum renkle değil ikon + yazıyla anlatılır.
class MikrofonHero extends StatelessWidget {
  final VoiceController controller;
  final ListenSource source;

  /// true: bulunduğu alanın tamamını kaplar (TalkBack kipinde Konuş ekranı).
  final bool expand;

  const MikrofonHero({
    super.key,
    required this.controller,
    this.source = ListenSource.screen,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (icon, text, semanticLabel) = switch (controller.phase) {
          VoicePhase.idle => (Icons.mic, Tr.voiceButton, Tr.voiceButtonLabel),
          VoicePhase.preparing || VoicePhase.listening => (
              Icons.stop_rounded,
              Tr.voiceListeningButton,
              Tr.voiceListeningLabel,
            ),
          VoicePhase.processing => (
              Icons.hourglass_top,
              Tr.voiceProcessingButton,
              Tr.voiceProcessingLabel,
            ),
        };
        final radius = BorderRadius.circular(PatikaTokens.radiusHero);

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: PatikaTokens.heroShadow,
          ),
          child: ElevatedButton(
            onPressed: () => controller.startListening(source),
            style: ElevatedButton.styleFrom(
              minimumSize: expand
                  ? const Size(double.infinity, double.infinity)
                  : const Size(double.infinity, 120),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: PatikaTokens.onHero,
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: PatikaCard.heroGradient,
                borderRadius: radius,
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: ExcludeSemantics(child: HeroDecorations())),
                  Semantics(
                    label: semanticLabel,
                    excludeSemantics: true,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              Tr.voiceHeroCaption,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 14),
                            _MicCircle(icon: icon, active: controller.isActive),
                            const SizedBox(height: 14),
                            Text(
                              text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              Tr.voiceHeroExamples,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Beyaz mikrofon dairesi ve (dinlerken) çevresindeki nabız halkaları.
class _MicCircle extends StatelessWidget {
  static const size = 104.0;

  final IconData icon;
  final bool active;

  const _MicCircle({required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dinlerken nabız: yalnızca bu durumda ağaçta (bitince denetleyici
          // dispose edilir); hareketi azalt açıkken durağan.
          if (active)
            const ExcludeSemantics(
              key: ValueKey('mikrofon-halkalari'),
              child: NabizHalkalari(size: size, color: PatikaTokens.onHero),
            ),
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: PatikaTokens.onHero,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 46, color: PatikaTokens.primary),
          ),
        ],
      ),
    );
  }
}
