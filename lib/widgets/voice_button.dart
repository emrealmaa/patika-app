import 'package:flutter/material.dart';

import '../l10n/strings_tr.dart';
import '../theme/app_theme.dart';
import '../voice/voice_controller.dart';

/// Dinlemeyi başlatan/iptal eden büyük buton - [VoiceController]'ın
/// görünümü. Mantık tamamen denetleyicide; bu widget yalnızca durumu
/// gösterir ve dokunuşu iletir.
///
/// Durum renkle değil metin + ikonla anlatılıyor, renk yardımcı işaret.
/// TalkBack'e ikon ve kısa görsel metin yerine tek, açıklayıcı bir etiket
/// okunuyor.
class VoiceButton extends StatelessWidget {
  final VoiceController controller;

  /// true: bulunduğu alanın tamamını kaplar (Konuş sekmesi).
  final bool expand;
  final ListenSource source;

  const VoiceButton({
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
              Icons.stop_circle_outlined,
              Tr.voiceListeningButton,
              Tr.voiceListeningLabel,
            ),
          VoicePhase.processing => (
              Icons.hourglass_top,
              Tr.voiceProcessingButton,
              Tr.voiceProcessingLabel,
            ),
        };

        return ElevatedButton(
          onPressed: () => controller.startListening(source),
          style: ElevatedButton.styleFrom(
            minimumSize: expand
                ? const Size(double.infinity, double.infinity)
                : const Size(double.infinity, 120),
            backgroundColor: controller.isActive ? PatikaTokens.accent : PatikaTokens.primary,
            foregroundColor:
                controller.isActive ? PatikaTokens.onAccent : PatikaTokens.onPrimary,
            textStyle: TextStyle(
              fontSize: expand ? 32 : 22,
              fontWeight: FontWeight.bold,
            ),
            shape: expand
                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                : null,
          ),
          child: Semantics(
            label: semanticLabel,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: expand ? 96 : 48),
                  const SizedBox(height: 8),
                  Text(text, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
