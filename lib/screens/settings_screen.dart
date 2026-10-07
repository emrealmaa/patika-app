import 'package:flutter/material.dart';

import '../accessibility/feedback_hub.dart';
import '../accessibility/haptic_patterns.dart';
import '../l10n/strings_tr.dart';
import '../platform/app_version.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../settings/test_mode_access.dart';
import '../sos/sos_config.dart';
import '../theme/app_theme.dart';
import '../widgets/anahtar_satiri.dart';
import '../widgets/ekran_basligi.dart';
import '../widgets/kisa_ozet_kart.dart';
import '../widgets/patika_card.dart';

/// Ayarlar ekranı. Tamamen TalkBack ile kullanılabilir olacak şekilde
/// radyo listeleri ve anahtarlardan oluşuyor (kaydırıcı yok - TalkBack'te
/// kademeli ayar zahmetli): her seçenek tam genişlikte, en az 56dp, TalkBack
/// "seçili, 3/5" gibi konumu kendisi okuyor. Bölümler kart içinde; uzun
/// açıklamalar tek cümlelik özet + "Ayrıntıyı göster" ([KisaOzetKart]).
/// Sonucu olan bilgi (112 ceza uyarısı) özette kalır.
///
/// Çift okuma olmasın diye TTS sadece konuşma hızı/ses tonu değişince
/// konuşuyor - yeni hızın/tonun önizlemesi olarak. Diğer seçimleri TalkBack
/// zaten okuyor. Titreşim şiddeti değişince örnek bir titreşim çalınıyor.
class SettingsScreen extends StatelessWidget {
  final SettingsStore store;
  final FeedbackHub feedback;
  final VoidCallback onStartTutorial;

  /// Sürüm satırı ve gizli Test Modu erişimi. İkisi de verilmezse satır
  /// gösterilmez.
  final TestModeAccess? testMode;
  final AppVersionSource? version;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.feedback,
    required this.onStartTutorial,
    this.testMode,
    this.version,
  });

  Settings get _s => store.value;

  void _update(Settings next) => store.update(next);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PatikaTokens.screenPadding,
        PatikaTokens.gap,
        PatikaTokens.screenPadding,
        PatikaTokens.gap,
      ),
      children: [
        const EkranBasligi(Tr.screenTitleSettings),
        _Section(Tr.settingsSpeech, [
          _Choice<int>(
            title: Tr.speechRate,
            value: s.speechRateLevel,
            options: [
              for (var i = 0; i < Settings.speechRates.length; i++)
                (i, Tr.speechRateNames[i], null),
            ],
            onChanged: (v) {
              final next = s.copyWith(speechRateLevel: v);
              _update(next);
              feedback.say(Tr.settingChanged(Tr.speechRate, next.speechRateName));
            },
          ),
          _Choice<int>(
            title: Tr.pitch,
            value: s.pitchLevel,
            options: [
              for (var i = 0; i < Settings.pitches.length; i++) (i, Tr.pitchNames[i], null),
            ],
            onChanged: (v) {
              final next = s.copyWith(pitchLevel: v);
              _update(next);
              feedback.say(Tr.settingChanged(Tr.pitch, next.pitchName));
            },
          ),
          _Choice<Verbosity>(
            title: Tr.verbosity,
            value: s.verbosity,
            options: const [
              (Verbosity.short, Tr.verbosityShort, Tr.verbosityShortHint),
              (Verbosity.long, Tr.verbosityLong, Tr.verbosityLongHint),
            ],
            onChanged: (v) => _update(s.copyWith(verbosity: v)),
          ),
        ]),
        _Section(Tr.settingsListening, [
          _Choice<int>(
            title: Tr.silenceTimeout,
            hint: Tr.silenceTimeoutHint,
            value: s.silenceTimeoutSeconds,
            options: [
              for (var i = Settings.minSilenceSeconds; i <= Settings.maxSilenceSeconds; i++)
                (i, Tr.seconds(i), null),
            ],
            onChanged: (v) => _update(s.copyWith(silenceTimeoutSeconds: v)),
          ),
          AnahtarSatiri(
            title: Tr.nodToListen,
            value: s.nodToListen,
            onChanged: (v) => _update(s.copyWith(nodToListen: v)),
          ),
          const KisaOzetKart(
            card: false,
            contextLabel: Tr.nodToListen,
            summary: Tr.nodToListenSummary,
            details: Tr.nodToListenDetails,
          ),
          AnahtarSatiri(
            title: Tr.readMessagesAloud,
            subtitle: Tr.readMessagesAloudHint,
            value: s.readMessagesAloud,
            onChanged: (v) => _update(s.copyWith(readMessagesAloud: v)),
          ),
          AnahtarSatiri(
            title: Tr.muteNotifications,
            value: s.notificationsMuted,
            onChanged: (v) => _update(s.copyWith(notificationsMuted: v)),
          ),
          const KisaOzetKart(
            card: false,
            contextLabel: Tr.muteNotifications,
            summary: Tr.muteNotificationsSummary,
            details: Tr.muteNotificationsDetails,
          ),
        ]),
        _Section(Tr.sosSettingsSection, [
          AnahtarSatiri(
            icon: Icons.phone_in_talk,
            danger: true,
            title: Tr.sosCall112Title,
            value: s.emergencyCall112,
            onChanged: (v) {
              _update(s.copyWith(emergencyCall112: v));
              // Açarken sesli uyarı (asılsız 112 aramasının yaptırımı var);
              // kapatınca da ne olacağı söylenir. Yeni değeri TalkBack
              // "açık/kapalı" diye okuyor, uyarı içeriği TTS'ten.
              feedback.say(v ? Tr.sosCall112EnabledWarning : Tr.sosCall112DisabledInfo);
            },
          ),
          // Ceza uyarısı özette (ayrıntıya saklanmaz).
          const KisaOzetKart(
            card: false,
            contextLabel: Tr.sosCall112Title,
            summary: Tr.sosCall112Summary,
            details: Tr.sosCall112Details,
          ),
        ]),
        const SizedBox(height: 12),
        KisaOzetKart(
          title: Tr.sosHowTitle,
          summary: Tr.sosHowSummary(SosConfig.manualCountdown.inSeconds),
          details: Tr.sosHowDetails,
        ),
        _Section(Tr.settingsFeedback, [
          _Choice<FeedbackMode>(
            title: Tr.feedbackMode,
            value: s.feedbackMode,
            options: const [
              (FeedbackMode.speech, Tr.feedbackSpeech, Tr.feedbackSpeechHint),
              (FeedbackMode.earconOnly, Tr.feedbackEarcon, Tr.feedbackEarconHint),
            ],
            onChanged: (v) => _update(s.copyWith(feedbackMode: v)),
          ),
          _Choice<int>(
            title: Tr.hapticStrength,
            value: s.hapticLevel,
            options: [
              for (var i = 0; i < Settings.hapticScales.length; i++) (i, Tr.hapticNames[i], null),
            ],
            onChanged: (v) {
              final next = s.copyWith(hapticLevel: v);
              _update(next);
              feedback.haptics.play(HapticPatternId.understood, scale: next.hapticScale);
            },
          ),
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onStartTutorial,
          icon: const Icon(Icons.school),
          label: const Text(Tr.startTutorial),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            _update(const Settings());
            feedback.say(Tr.settingsReset);
          },
          icon: const Icon(Icons.restore),
          label: const Text(Tr.resetSettings),
        ),
        const SizedBox(height: 12),
        if (version != null)
          _VersionTile(version: version!, testMode: testMode, feedback: feedback),
      ],
    );
  }
}

/// Sürüm satırı. Gizli erişim burada: art arda 7 dokunuş Test Modu'nu açar
/// (Android "Geliştirici seçenekleri" deseni). Satır sıradan bir bilgi satırı
/// gibi görünür ve okunur (TalkBack'te yalnızca "Sürüm 1.0.0 (1)"); her
/// dokunuşta kısa titreşim, 4. dokunuştan itibaren sesli sayaç, 7.'de sesli
/// "Test modu açıldı" bildirimi gelir, böylece TalkBack ile de yapılabilir.
class _VersionTile extends StatelessWidget {
  final AppVersionSource version;
  final TestModeAccess? testMode;
  final FeedbackHub feedback;

  const _VersionTile({required this.version, required this.testMode, required this.feedback});

  void _onTap() {
    final access = testMode;
    if (access == null) return;
    final result = access.tap();
    switch (result.kind) {
      case TestModeTapKind.counting:
        _tick();
      case TestModeTapKind.countdown:
        _tick();
        // Önceki sayaç cümlesi bitmeden yenisi gelirse eskisi kesilir.
        feedback.queue.stopAll();
        feedback.say(Tr.testModeTapsLeft(result.remaining), dedupe: false);
      case TestModeTapKind.unlocked:
        feedback.queue.stopAll();
        feedback.signal(FeedbackEvent.success, text: Tr.testModeOpened);
      case TestModeTapKind.alreadyUnlocked:
        feedback.queue.stopAll();
        feedback.say(Tr.testModeAlreadyOpen, dedupe: false);
    }
  }

  void _tick() =>
      feedback.haptics.play(HapticPatternId.listening, scale: feedback.settings.hapticScale);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: version.label(),
      builder: (context, snapshot) {
        final text = snapshot.data ?? '';
        return Semantics(
          container: true,
          label: text,
          excludeSemantics: true,
          // Düğme DEĞİL: kullanıcıya "düğme" denmez; TalkBack çift dokunuşu
          // yine de iletir (tap eylemi var).
          onTap: testMode == null ? null : _onTap,
          child: InkWell(
            onTap: testMode == null ? null : _onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bölüm: küçük başlık (TalkBack'te header) + içindekileri saran kart.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, PatikaTokens.gapSmall),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: PatikaTokens.textSecondary),
            ),
          ),
        ),
        PatikaCard(
          padding: const EdgeInsets.symmetric(horizontal: PatikaTokens.gap, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Başlık + (varsa) açıklama + radyo seçenekleri. Seçim durumu radyo
/// düğmesinin kendisiyle ve TalkBack'in "seçili" bilgisiyle anlatılıyor,
/// renkle değil.
class _Choice<T> extends StatelessWidget {
  final String title;
  final String? hint;
  final T value;
  final List<(T, String, String?)> options;
  final ValueChanged<T> onChanged;

  const _Choice({
    super.key,
    required this.title,
    this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            header: true,
            child: Text(title, style: text.titleSmall),
          ),
        ),
        if (hint != null)
          Text(hint!, style: text.bodySmall?.copyWith(color: PatikaTokens.textSecondary)),
        RadioGroup<T>(
          groupValue: value,
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
          child: Column(
            children: [
              for (final (optionValue, label, optionHint) in options)
                RadioListTile<T>(
                  value: optionValue,
                  // Ayar adı her seçenekte okunsun: "Konuşma hızı: Hızlı" -
                  // listenin ortasına odaklanan kullanıcı neyi seçtiğini
                  // bilsin. Seçili durumunu TalkBack kendisi ekliyor.
                  title: Semantics(
                    label: Tr.settingOption(title, label),
                    excludeSemantics: true,
                    child: Text(label),
                  ),
                  subtitle: optionHint == null ? null : Text(optionHint),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: PatikaTokens.minTouch,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
