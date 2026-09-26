import 'package:flutter/material.dart';

import '../accessibility/announcement_queue.dart';
import '../accessibility/earcons.dart';
import '../accessibility/feedback_hub.dart';
import '../accessibility/haptic_patterns.dart';
import '../app_state.dart';
import '../ble/glasses_protocol.dart';
import '../ble/simulated_ble_service.dart';
import '../commands/log_entry.dart';
import '../commands/voice_intent_classifier.dart';
import '../l10n/strings_tr.dart';
import '../settings/settings.dart';
import '../theme/app_theme.dart';
import '../voice/speech_input_service.dart';

/// Gözlük donanımı olmadan komut akışını (parse -> route -> handler -> log)
/// uçtan uca test etmek için sahte komut enjekte eden ekran. Sadece
/// simülasyon modundayken anlamlı - gerçek moddayken bir uyarı gösterir.
class TestModeScreen extends StatefulWidget {
  final AppState state;

  const TestModeScreen({super.key, required this.state});

  @override
  State<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends State<TestModeScreen> {
  final _entityController = TextEditingController();
  String _selectedIntent = 'ARA';

  static const _intents = [
    'ARA',
    'MESAJ',
    'HAVA',
    'SAAT',
    'MÜZİK',
    'HABER',
    'OKU',
    'GECIS_MODU',
    'NAVİGASYON',
    'AYAR',
    'BİLİNMİYOR',
  ];

  @override
  void dispose() {
    _entityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _VoiceCommandButton(state: state),
        const SizedBox(height: 24),
        if (!state.isSimulated)
          Card(
            // Uyarı zaten metinle anlatılıyor (Kural 5) - burada sadece
            // koyu zemin + beyaz metinle AAA kontrastı garanti ediliyor
            // (açık sarı zemin + varsayılan koyu metin karanlık temada
            // düşük kontrast üretirdi).
            color: const Color(0xFF4A3600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.warning),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  ExcludeSemantics(child: Icon(Icons.warning_amber, color: AppColors.warning)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Tr.manualOnlySimulated,
                      style: TextStyle(color: AppColors.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedIntent,
          decoration: const InputDecoration(labelText: Tr.intentLabel),
          items: _intents
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: (v) => setState(() => _selectedIntent = v ?? _selectedIntent),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _entityController,
          decoration: const InputDecoration(
            labelText: Tr.entityLabel,
            hintText: Tr.entityHint,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: state.isSimulated
              ? () {
                  final entity = _entityController.text.trim();
                  state.injectTestCommand(
                    _selectedIntent,
                    entity: entity.isEmpty ? null : entity,
                  );
                }
              : null,
          icon: const Icon(Icons.send),
          label: const Text(Tr.sendCommand),
        ),
        if (state.simulator case final sim?) ...[
          const SizedBox(height: 24),
          _GlassesSimulationSection(simulator: sim, lastEvent: state.lastGlassesEvent),
        ],
        const SizedBox(height: 24),
        _FeedbackTestSection(feedback: state.feedback),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.commandHistory, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        if (state.log.isEmpty)
          const Text(Tr.noCommands)
        else
          ...state.log.map((e) => _LogCard(entry: e)),
      ],
    );
  }
}

enum _VoicePhase { idle, preparing, listening, processing }

/// Telefonun kendi mikrofonuyla komut verme butonu - girdi kaynağı klavye
/// yerine ses; tanınan metin [classifyVoiceCommand] ile BleCommand'e
/// çevrilip diğer kaynaklarla aynı yoldan (AppState -> CommandRouter)
/// işleniyor.
///
/// Basılı tutma yerine dokunarak aç/kapat: TalkBack/VoiceOver açıkken
/// basılı tutmak "çift dokun ve tut" gerektirir, görme engelli kullanıcı
/// için zahmetli. Motor, kullanıcı susunca dinlemeyi kendisi bitirir.
class _VoiceCommandButton extends StatefulWidget {
  final AppState state;

  const _VoiceCommandButton({required this.state});

  @override
  State<_VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<_VoiceCommandButton> {
  /// Duyuru ile sonraki adım arasındaki bekleme. TTS'in bitişi burada
  /// beklenmiyor; bu olmadan "Dinliyorum" sesi mikrofona komut olarak
  /// girebilir ya da "Şunu anladım" duyurusu komut sonucunun duyurusuyla
  /// kesilebilir. "Sadece kısa ses" modunda kısa ses ~0,2 sn sürdüğü için
  /// bekleme de kısa.
  static const _speechGap = Duration(milliseconds: 1200);
  static const _earconGap = Duration(milliseconds: 400);

  final _speech = SpeechInputService();
  _VoicePhase _phase = _VoicePhase.idle;
  String? _lastHeard;

  FeedbackHub get _feedback => widget.state.feedback;

  Duration get _gap => _feedback.settings.feedbackMode == FeedbackMode.speech
      ? _speechGap
      : _earconGap;

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  void _setPhase(_VoicePhase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  Future<void> _onTap() async {
    switch (_phase) {
      case _VoicePhase.processing:
        return;
      case _VoicePhase.preparing:
      case _VoicePhase.listening:
        await _speech.cancel();
        _setPhase(_VoicePhase.idle);
        _feedback.signal(FeedbackEvent.listenEnded, statusText: Tr.listenCancelled);
        return;
      case _VoicePhase.idle:
        break;
    }

    _setPhase(_VoicePhase.preparing);
    final ready = await _speech.init();
    if (_phase != _VoicePhase.preparing) return;
    if (!ready) {
      _setPhase(_VoicePhase.idle);
      _feedback.signal(FeedbackEvent.error, text: Tr.speechUnavailable);
      return;
    }

    _feedback.signal(FeedbackEvent.listening, statusText: Tr.listening);
    await Future.delayed(_gap);
    // Beklerken iptal edildiyse ya da ekrandan çıkıldıysa dinlemeye başlama.
    if (!mounted || _phase != _VoicePhase.preparing) return;

    _setPhase(_VoicePhase.listening);
    await _speech.listen(
      onFinal: _onFinal,
      onError: _onError,
      onDone: () => _onError(Tr.didNotHear),
      silenceTimeout: _feedback.settings.silenceTimeout,
    );
  }

  Future<void> _onFinal(String text) async {
    if (_phase != _VoicePhase.listening) return;
    if (text.isEmpty) {
      _onError(Tr.didNotHear);
      return;
    }

    setState(() {
      _phase = _VoicePhase.processing;
      _lastHeard = text;
    });
    _feedback.signal(FeedbackEvent.understood, text: Tr.heard(text));
    await Future.delayed(_speechGap);

    // Komut anlaşıldı - kullanıcı bu arada sekmeden çıksa bile işleniyor.
    // Sonuç duyurusunu AppState yapıyor (diğer kaynaklarla aynı).
    await widget.state.submitVoiceCommand(classifyVoiceCommand(text));
    _setPhase(_VoicePhase.idle);
  }

  void _onError(String message) {
    if (_phase != _VoicePhase.listening) return;
    _setPhase(_VoicePhase.idle);
    _feedback.signal(FeedbackEvent.notUnderstood, text: message);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, text, semanticLabel) = switch (_phase) {
      _VoicePhase.idle => (Icons.mic, Tr.voiceButton, Tr.voiceButtonLabel),
      _VoicePhase.preparing || _VoicePhase.listening => (
          Icons.stop_circle_outlined,
          Tr.voiceListeningButton,
          Tr.voiceListeningLabel,
        ),
      _VoicePhase.processing => (
          Icons.hourglass_top,
          Tr.voiceProcessingButton,
          Tr.voiceProcessingLabel,
        ),
    };
    // Durum renkle değil metin+ikonla anlatılıyor; renk yardımcı işaret.
    final active = _phase != _VoicePhase.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _onTap,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 120),
            backgroundColor: active ? AppColors.warning : AppColors.info,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          // Buton kendi alt ağacının etiketini birleştiriyor; ikon ve kısa
          // görsel metin yerine tek, açıklayıcı bir etiket okunsun.
          child: Semantics(
            label: semanticLabel,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48),
                  const SizedBox(height: 8),
                  Text(text, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        if (_lastHeard != null) ...[
          const SizedBox(height: 8),
          Text(Tr.lastHeard(_lastHeard!)),
        ],
      ],
    );
  }
}

/// Gözlüğün buton/jest/pil olaylarını ve bağlantı sorunlarını (donma,
/// menzil dışı) donanımsız taklit eder - bağlantı denetçisinin heartbeat
/// ve yeniden bağlanma davranışı buradan denenebilir.
class _GlassesSimulationSection extends StatefulWidget {
  final SimulatedBleService simulator;
  final String? lastEvent;

  const _GlassesSimulationSection({required this.simulator, this.lastEvent});

  @override
  State<_GlassesSimulationSection> createState() => _GlassesSimulationSectionState();
}

class _GlassesSimulationSectionState extends State<_GlassesSimulationSection> {
  late double _battery = widget.simulator.battery.toDouble();

  SimulatedBleService get _sim => widget.simulator;

  @override
  Widget build(BuildContext context) {
    final lastEvent = widget.lastEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // container: true -> düz metinler üstteki düğüme birleşip tek bir
        // uzun etiket olarak okunmasın (emülatör erişilebilirlik ağacında
        // görüldü).
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.glassesSimulation, style: Theme.of(context).textTheme.titleMedium),
        ),
        Semantics(container: true, child: const Text(Tr.glassesSimulationHint)),
        const SizedBox(height: 12),
        for (final (label, action) in [
          (Tr.buttonTap, () => _sim.injectButton(GlassesButton.tap)),
          (Tr.buttonDoubleTap, () => _sim.injectButton(GlassesButton.doubleTap)),
          (Tr.buttonLongPress, () => _sim.injectButton(GlassesButton.longPress)),
          (Tr.gestureDoubleNod, () => _sim.injectGesture(GlassesGesture.doubleNod)),
        ]) ...[
          OutlinedButton(onPressed: action, child: Text(label)),
          const SizedBox(height: 8),
        ],
        if (lastEvent != null)
          Semantics(container: true, child: Text(Tr.glassesEvent(lastEvent))),
        const SizedBox(height: 8),
        // Görsel başlık; TalkBack aynı bilgiyi kaydırıcının kendisinden duyar.
        ExcludeSemantics(
          child: Text('${Tr.glassesBattery}: %${_battery.round()}',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        Slider(
          min: 0,
          max: 100,
          divisions: 20,
          value: _battery,
          // `label` verilmiyor: TalkBack onu değerle birlikte ikinci kez okuyor.
          semanticFormatterCallback: (v) => '${Tr.glassesBattery}: ${Tr.percent(v.round())}',
          onChanged: (v) => setState(() => _battery = v),
          onChangeEnd: (v) => _sim.setBattery(v.round()),
        ),
        SwitchListTile(
          title: const Text(Tr.heartbeatPaused),
          subtitle: const Text(Tr.heartbeatPausedHint),
          value: _sim.heartbeatPaused,
          onChanged: (v) => setState(() => _sim.setHeartbeatPaused(v)),
        ),
        SwitchListTile(
          title: const Text(Tr.glassesUnreachable),
          subtitle: const Text(Tr.glassesUnreachableHint),
          value: !_sim.reachable,
          onChanged: (v) => setState(() => _sim.setReachable(!v)),
        ),
        ValueListenableBuilder<HapticPatternId?>(
          valueListenable: _sim.lastHaptic,
          builder: (context, id, _) => id == null
              ? const SizedBox.shrink()
              : Semantics(
                  container: true,
                  child: Text(Tr.lastHaptic(Tr.hapticName(id.name))),
                ),
        ),
      ],
    );
  }
}

/// Titreşim dili, kısa sesler, duyuru önceliği ve engel titreşimini
/// donanımsız denemek için. Hepsi FeedbackHub üzerinden gidiyor - ayarlar
/// (titreşim şiddeti, bildirim türü) burada da geçerli.
class _FeedbackTestSection extends StatefulWidget {
  final FeedbackHub feedback;

  const _FeedbackTestSection({required this.feedback});

  @override
  State<_FeedbackTestSection> createState() => _FeedbackTestSectionState();
}

class _FeedbackTestSectionState extends State<_FeedbackTestSection> {
  HapticPatternId _pattern = HapticPatternId.connected;
  Earcon _earcon = Earcon.listenStart;
  bool _obstacleOn = false;
  double _obstacleMeters = 1.5;

  FeedbackHub get _feedback => widget.feedback;

  @override
  void dispose() {
    // Ekrandan çıkınca test titreşimi sürmesin.
    _feedback.updateObstacle(null);
    super.dispose();
  }

  void _updateObstacle() =>
      _feedback.updateObstacle(_obstacleOn ? _obstacleMeters : null);

  void _runPriorityTest() {
    _feedback.say(Tr.priorityTestLow, priority: AnnouncementPriority.low);
    Future.delayed(const Duration(milliseconds: 1500), () {
      _feedback.say(Tr.priorityTestCritical, priority: AnnouncementPriority.critical);
    });
  }

  @override
  Widget build(BuildContext context) {
    final interval = HapticPatterns.obstacleInterval(_obstacleMeters);
    final distanceText =
        interval == null ? Tr.obstacleNone : Tr.meters(_obstacleMeters);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.feedbackTest, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<HapticPatternId>(
          initialValue: _pattern,
          decoration: const InputDecoration(labelText: Tr.hapticPatternLabel),
          items: HapticPatternId.values
              .map((p) => DropdownMenuItem(value: p, child: Text(Tr.hapticName(p.name))))
              .toList(),
          onChanged: (v) => setState(() => _pattern = v ?? _pattern),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _feedback.haptics
              .play(_pattern, scale: _feedback.settings.hapticScale),
          icon: const Icon(Icons.vibration),
          label: const Text(Tr.playHaptic),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Earcon>(
          initialValue: _earcon,
          decoration: const InputDecoration(labelText: Tr.earconLabel),
          items: Earcon.values
              .map((e) => DropdownMenuItem(value: e, child: Text(Tr.earconName(e.name))))
              .toList(),
          onChanged: (v) => setState(() => _earcon = v ?? _earcon),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _feedback.earcons.play(_earcon),
          icon: const Icon(Icons.music_note),
          label: const Text(Tr.playEarcon),
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: Tr.priorityTestLabel,
          excludeSemantics: true,
          child: OutlinedButton.icon(
            onPressed: _runPriorityTest,
            icon: const Icon(Icons.low_priority),
            label: const Text(Tr.priorityTest),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text(Tr.obstacleSimulation),
          subtitle: Text(distanceText),
          value: _obstacleOn,
          onChanged: (v) {
            setState(() => _obstacleOn = v);
            _updateObstacle();
          },
        ),
        Slider(
          min: 0.2,
          max: 3.0,
          divisions: 28,
          value: _obstacleMeters,
          // Ad kaydırıcının kendi etiketinde; ayrı bir Semantics sarmalayıcısı
          // adı üstteki bölüm başlığına yapıştırıyordu.
          semanticFormatterCallback: (v) {
            final interval = HapticPatterns.obstacleInterval(v);
            return '${Tr.obstacleDistance}: ${interval == null ? Tr.obstacleNone : Tr.meters(v)}';
          },
          onChanged: (v) {
            setState(() => _obstacleMeters = v);
            _updateObstacle();
          },
        ),
      ],
    );
  }
}

/// Görsel düzen (ikon + başlık + alt yazı + saat, `ListTile` içinde)
/// bilinçli olarak korundu - TalkBack zaten lineer okuyor, yan yana rakip
/// kontrol değil sıralı bilgi. Buradaki tek değişiklik: ikon+renk artık TEK
/// BAŞINA "başarılı/başarısız" anlamı taşımıyor, saat de artık anlamlı bir
/// etikete sahip - tüm satır tek, açık bir Semantics etiketine sarılı.
class _LogCard extends StatelessWidget {
  final LogEntry entry;

  const _LogCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ok = entry.result.success;
    final baslik = '${entry.intent.name}${entry.entity != null ? " (${entry.entity})" : ""}';
    final saat = '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}';

    return Semantics(
      label: '${Tr.logEntryLabel(baslik, ok, entry.result.message)}. ${Tr.logEntryTime(saat)}',
      excludeSemantics: true,
      child: Card(
        child: ListTile(
          leading: ExcludeSemantics(
            child: Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? AppColors.success : AppColors.warning,
            ),
          ),
          title: Text(baslik),
          subtitle: Text('${ok ? Tr.success : Tr.failure}: ${entry.result.message}'),
          trailing: Text(saat),
        ),
      ),
    );
  }
}
