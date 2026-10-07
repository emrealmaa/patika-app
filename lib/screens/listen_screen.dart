import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings_tr.dart';
import '../theme/app_theme.dart';
import '../voice/voice_controller.dart';
import '../widgets/durum_hapi.dart';
import '../widgets/mikrofon_hero.dart';
import '../widgets/patika_card.dart';
import '../widgets/voice_button.dart';

/// Uygulamanın ilk sekmesi: tek iş, dinlemeyi başlatmak.
///
/// TalkBack açıkken ekranın TAMAMI tek bir buton: görme engelli kullanıcı
/// ekranın neresine dokunursa dokunsun "Konuş" odağa gelir, çift dokunuş
/// dinlemeyi başlatır - hedef aramak gerekmez. TalkBack kapalıyken üstte
/// gözlük durumu ve pil kartları, ortada büyük dinleme düğmesi
/// ([MikrofonHero]), altta son duyulan cümle.
class ListenScreen extends StatelessWidget {
  final AppState state;

  const ListenScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final voice = state.voice;
    if (MediaQuery.accessibleNavigationOf(context)) {
      return Padding(
        padding: const EdgeInsets.all(PatikaTokens.gapSmall),
        child: MikrofonHero(controller: voice, expand: true),
      );
    }

    final connected = state.isHealthy;
    // Ekran küçükse ya da yazı büyütülmüşse kaydırılır; yer varsa düğme
    // kalan alanı doldurur.
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PatikaTokens.screenPadding,
              PatikaTokens.gapSmall,
              PatikaTokens.screenPadding,
              PatikaTokens.gap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: connected
                      ? DurumHapi.basari(Tr.glassesStatusLine(true))
                      : DurumHapi.notr(Tr.glassesStatusLine(false)),
                ),
                const SizedBox(height: PatikaTokens.gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PilKarti(
                          icon: Icons.visibility_outlined,
                          title: Tr.glassesBatteryTitle,
                          percent: connected ? state.glassesBattery : null,
                          fallback: Tr.batteryCardNotConnected,
                          semanticLabel: Tr.glassesBatteryCardLabel(
                            connected ? state.glassesBattery : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PilKarti(
                          icon: Icons.smartphone,
                          title: Tr.phoneBatteryTitle,
                          percent: state.phoneBatteryPercent,
                          fallback: Tr.batteryCardUnknown,
                          note: state.phoneCharging == true ? Tr.batteryCardCharging : null,
                          semanticLabel: Tr.phoneBatteryCardLabel(
                            state.phoneBatteryPercent,
                            state.phoneCharging == true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PatikaTokens.gap),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 320),
                    child: MikrofonHero(controller: voice),
                  ),
                ),
                ListenableBuilder(
                  listenable: voice,
                  builder: (context, _) {
                    final heard = voice.lastHeard;
                    if (heard == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: PatikaTokens.gap),
                      child: PatikaCard(
                        child: Semantics(
                          container: true,
                          child: Text(
                            Tr.lastHeard(heard),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pil kartı: başlık, büyük yüzde (ya da "Bağlı değil"/"Okunamadı") ve
/// doluluk çubuğu. TalkBack tek cümle okur ("Telefon pili yüzde 64, şarj
/// oluyor"); ikon ve çubuk süstür.
class _PilKarti extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? percent;
  final String fallback;
  final String? note;
  final String semanticLabel;

  const _PilKarti({
    required this.icon,
    required this.title,
    required this.percent,
    required this.fallback,
    required this.semanticLabel,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = this.percent;
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PatikaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: PatikaTokens.primary),
                const SizedBox(width: PatikaTokens.gapSmall),
                Flexible(
                  child: Text(
                    title,
                    style: text.bodySmall?.copyWith(
                      color: PatikaTokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              percent == null ? fallback : Tr.batteryPercentShort(percent),
              style: percent == null ? text.titleSmall : text.headlineSmall,
            ),
            if (note != null)
              Text(note!, style: text.bodySmall?.copyWith(color: PatikaTokens.textSecondary)),
            if (percent != null) ...[
              const SizedBox(height: PatikaTokens.gapSmall),
              ClipRRect(
                borderRadius: BorderRadius.circular(PatikaTokens.radiusPill),
                child: LinearProgressIndicator(
                  value: percent.clamp(0, 100) / 100,
                  minHeight: 6,
                  color: PatikaTokens.primary,
                  backgroundColor: PatikaTokens.primarySoft,
                ),
              ),
            ],
          ],
        ),
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
