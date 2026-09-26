import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings_tr.dart';
import '../voice/voice_controller.dart';
import '../widgets/voice_button.dart';

/// Uygulamanın ilk sekmesi: tek iş, dinlemeyi başlatmak.
///
/// TalkBack açıkken ekranın TAMAMI tek bir buton: görme engelli kullanıcı
/// ekranın neresine dokunursa dokunsun "Konuş" odağa gelir, çift dokunuş
/// dinlemeyi başlatır - hedef aramak gerekmez. TalkBack kapalıyken büyük
/// butonun altında kısa bir durum satırı ve son duyulan cümle var.
class ListenScreen extends StatelessWidget {
  final AppState state;

  const ListenScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final voice = state.voice;
    if (MediaQuery.accessibleNavigationOf(context)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: VoiceButton(controller: voice, expand: true),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: VoiceButton(controller: voice, expand: true)),
          const SizedBox(height: 16),
          Semantics(
            container: true,
            child: Text(
              Tr.glassesStatusLine(state.isHealthy),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          ListenableBuilder(
            listenable: voice,
            builder: (context, _) {
              final heard = voice.lastHeard;
              if (heard == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  container: true,
                  child: Text(Tr.lastHeard(heard), textAlign: TextAlign.center),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Test ekranı gibi yerlerde kullanılan küçük sürüm.
class CompactVoiceButton extends StatelessWidget {
  final VoiceController controller;

  const CompactVoiceButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VoiceButton(controller: controller, source: ListenSource.test),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final heard = controller.lastHeard;
            if (heard == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(container: true, child: Text(Tr.lastHeard(heard))),
            );
          },
        ),
      ],
    );
  }
}
