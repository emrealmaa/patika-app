import 'package:flutter/material.dart';

import '../accessibility/feedback_hub.dart';
import '../accessibility/haptic_patterns.dart';
import '../fall/fall_enable_session.dart';
import '../fall/fall_mode.dart';
import '../fall/fall_open_text.dart';
import '../fall/fall_settings_controller.dart';
import '../l10n/strings_tr.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../widgets/fall_enable_dialog.dart';

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

  /// Düşme algılama bölümünün bağımlılığı (Faz 7c-2). Null ise bölüm hiç
  /// gösterilmez.
  final FallSettingsController? fall;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.feedback,
    required this.onStartTutorial,
    this.fall,
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
        if (fall != null) ...[
          _Header(Tr.fallSettingsSection),
          _FallSection(controller: fall!, feedback: feedback),
        ],
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
      ],
    );
  }
}

/// "Düşme algılama (deneysel)" bölümü (Faz 7c-2, karar 12): durum satırı,
/// gölge ANAHTARI (kolay açılıp kapanır) ve "Açık modu aç" DÜĞMESİ (anahtar
/// değil, eylem: iki adımlı açmayı başlatır). Engellenmiş durumda düğme etkin
/// kalır; basınca nedeni yazıyla ve sesle (TalkBack açıksa yalnızca TalkBack)
/// söyler (karar 12b).
class _FallSection extends StatefulWidget {
  final FallSettingsController controller;
  final FeedbackHub feedback;

  const _FallSection({required this.controller, required this.feedback});

  @override
  State<_FallSection> createState() => _FallSectionState();
}

class _FallSectionState extends State<_FallSection> {
  late Future<FallSettingsStatus> _status;

  /// Son eylemin sonucu / engel nedeni: ekranda yazılı kalır (TalkBack canlı
  /// bölge olarak okur); TalkBack kapalıyken ayrıca TTS okur.
  String? _message;

  @override
  void initState() {
    super.initState();
    _status = widget.controller.status();
    widget.controller.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant _FallSection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_reload);
      widget.controller.addListener(_reload);
    }
    // Üst ekran yeniden kuruldu (ayar/uygulama durumu değişti): özeti tazele.
    _status = widget.controller.status();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final next = widget.controller.status();
    setState(() {
      _status = next;
    });
  }

  void _announce(String text) {
    if (!mounted) return;
    setState(() => _message = text);
    // TalkBack açıkken canlı bölge okur; TTS de okusa çift okuma olurdu.
    if (!MediaQuery.accessibleNavigationOf(context)) widget.feedback.say(text);
  }

  Future<void> _setShadow(bool on) async {
    await widget.controller.setShadowEnabled(on);
    _announce(on ? Tr.fallShadowWarning : Tr.fallShadowDisabled);
  }

  Future<void> _toggleOpen() async {
    final c = widget.controller;
    if (c.mode == FallMode.on) {
      await c.closeOpenMode();
      _announce(Tr.fallOpenClosedToShadow);
      return;
    }
    final begin = await c.session.begin(FallEnableChannel.screen);
    if (!mounted) return;
    switch (begin.kind) {
      case FallEnableBeginKind.blocked:
        _announce(fallOpenBlockText(begin.gate!));
      case FallEnableBeginKind.alreadyOn:
        c.changed();
        _announce(Tr.fallOpenAlready);
      case FallEnableBeginKind.superseded:
        break;
      case FallEnableBeginKind.prompt:
        final result = await showFallEnableDialog(
          context,
          controller: c,
          begin: begin,
          feedback: widget.feedback,
        );
        if (!mounted) return;
        c.changed();
        _announce(switch (result?.kind) {
          FallEnableConfirmKind.enabled => Tr.fallOpenEnabled,
          FallEnableConfirmKind.expired => Tr.fallOpenExpired,
          FallEnableConfirmKind.blocked => fallOpenBlockText(result!.gate!),
          FallEnableConfirmKind.storageFailed => Tr.fallOpenStorageFailed,
          _ => Tr.fallOpenNotEnabled,
        });
    }
  }

  String _statusLine(FallSettingsStatus s) => switch (s.mode) {
        FallMode.off => Tr.fallStatusOffLine,
        FallMode.shadow => Tr.fallStatusShadowLine(s.runningDays, s.records),
        FallMode.on => Tr.fallStatusOnLine(s.runningDays, s.records),
      };

  @override
  Widget build(BuildContext context) {
    final mode = widget.controller.mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FutureBuilder<FallSettingsStatus>(
            future: _status,
            builder: (context, snapshot) {
              final s = snapshot.data;
              return Semantics(
                container: true,
                child: Text(s == null ? Tr.fallStatusOffLine : _statusLine(s)),
              );
            },
          ),
        ),
        SwitchListTile(
          title: const Text(Tr.fallShadowSwitchTitle),
          subtitle: const Text(Tr.fallShadowSwitchHint),
          value: mode != FallMode.off,
          onChanged: _setShadow,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.tonal(
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(56))),
            onPressed: _toggleOpen,
            child: Text(mode == FallMode.on ? Tr.fallOpenButtonClose : Tr.fallOpenButtonOpen),
          ),
        ),
        // Düğmenin altındaki not: kapalıyken nasıl açılacağı; açıkken de
        // gölgeyi tamamen kapatmanın AYRI yolu (anahtar) hatırlatılır.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(mode == FallMode.on ? Tr.fallOpenCloseNote : Tr.fallOpenButtonHint),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(liveRegion: true, container: true, child: Text(_message!)),
          ),
      ],
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
