import 'package:flutter/material.dart';

import '../accessibility/feedback_hub.dart';
import '../accessibility/haptic_patterns.dart';
import '../l10n/strings_tr.dart';
import '../platform/app_version.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../settings/test_mode_access.dart';

/// Ayarlar ekranı. Tamamen TalkBack ile kullanılabilir olacak şekilde
/// sadece radyo listelerinden oluşuyor (kaydırıcı yok - TalkBack'te kademeli
/// ayar zahmetli): her seçenek tam genişlikte, en az 56dp, TalkBack
/// "seçili, 3/5" gibi konumu kendisi okuyor.
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Header(Tr.settingsSpeech),
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
        _Header(Tr.settingsListening),
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
        SwitchListTile(
          title: const Text(Tr.nodToListen),
          subtitle: const Text(Tr.nodToListenHint),
          value: s.nodToListen,
          onChanged: (v) => _update(s.copyWith(nodToListen: v)),
        ),
        SwitchListTile(
          title: const Text(Tr.readMessagesAloud),
          subtitle: const Text(Tr.readMessagesAloudHint),
          value: s.readMessagesAloud,
          onChanged: (v) => _update(s.copyWith(readMessagesAloud: v)),
        ),
        SwitchListTile(
          title: const Text(Tr.muteNotifications),
          subtitle: const Text(Tr.muteNotificationsHint),
          value: s.notificationsMuted,
          onChanged: (v) => _update(s.copyWith(notificationsMuted: v)),
        ),
        _Header(Tr.sosSettingsSection),
        SwitchListTile(
          title: const Text(Tr.sosCall112Title),
          subtitle: const Text(Tr.sosCall112Hint),
          value: s.emergencyCall112,
          onChanged: (v) {
            _update(s.copyWith(emergencyCall112: v));
            // Açarken sesli uyarı (asılsız 112 aramasının yaptırımı var);
            // kapatınca da ne olacağı söylenir. Yeni değeri TalkBack
            // "açık/kapalı" diye okuyor, uyarı içeriği TTS'ten.
            feedback.say(v ? Tr.sosCall112EnabledWarning : Tr.sosCall112DisabledInfo);
          },
        ),
        _Header(Tr.settingsFeedback),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: OutlinedButton.icon(
            onPressed: onStartTutorial,
            icon: const Icon(Icons.school),
            label: const Text(Tr.startTutorial),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () {
              _update(const Settings());
              feedback.say(Tr.settingsReset);
            },
            icon: const Icon(Icons.restore),
            label: const Text(Tr.resetSettings),
          ),
        ),
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

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(hint!),
          ),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  minTileHeight: 56,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
