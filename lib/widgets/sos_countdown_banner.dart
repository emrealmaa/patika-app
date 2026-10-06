import 'package:flutter/material.dart';

import '../l10n/strings_tr.dart';
import '../sos/sos_config.dart';
import '../sos/sos_controller.dart';
import '../theme/app_theme.dart';

/// Acil durum geri sayımı sürerken tüm sekmelerin üstünde görünen şerit:
/// kalan süre ve büyük "İptal et" düğmesi (telefon ekranından iptal kanalı).
///
/// Bilgi yalnızca renkle verilmez: ikon + metin. Düğme en az 56 dp ve etiketi
/// düğmenin içinde (dışarıdan `excludeSemantics` ile sarılmıyor: TalkBack'te
/// dokunma eylemi kaybolurdu). Duyuru TalkBack'e değil TTS'e gider
/// (`FeedbackSosAnnouncer`), bu yüzden canlı bölge (liveRegion) kullanılmaz;
/// çift okuma olmaz.
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
            return _Panel(
              child: Row(
                children: const [
                  Icon(Icons.sms, color: PatikaTokens.sos),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      Tr.sosBannerSending,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: PatikaTokens.sos),
                    ),
                  ),
                ],
              ),
            );
          case SosPhase.countdown:
            final seconds = status.remaining.inSeconds;
            return _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: PatikaTokens.sos, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          Tr.sosBannerTitle(seconds),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold, color: PatikaTokens.sos),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => sos.cancel(SosCancelSource.screen),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: PatikaTokens.sos,
                      foregroundColor: PatikaTokens.onSos,
                      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    icon: const Icon(Icons.cancel),
                    label: const Text(Tr.sosCancelButton),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PatikaTokens.sosSurface,
      child: SafeArea(
        bottom: false,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
