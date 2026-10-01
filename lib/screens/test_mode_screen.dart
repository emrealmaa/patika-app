import 'package:flutter/material.dart';

import '../accessibility/announcement_queue.dart';
import '../accessibility/earcons.dart';
import '../accessibility/feedback_hub.dart';
import '../accessibility/haptic_patterns.dart';
import '../app_state.dart';
import '../ble/glasses_protocol.dart';
import '../battery/phone_battery.dart';
import '../ble/simulated_ble_service.dart';
import '../commands/log_entry.dart';
import '../l10n/strings_tr.dart';
import '../navigation/guidance_speech.dart';
import '../navigation/navigation_session.dart';
import '../navigation/simulated_walk.dart';
import '../permissions/permission_explainer.dart';
import '../platform/call_service.dart';
import '../platform/notification_access.dart';
import '../platform/simulated_call_service.dart';
import '../theme/app_theme.dart';
import 'listen_screen.dart';

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
    'SAAT',
    'OKU',
    'GECIS_MODU',
    'NAVİGASYON',
    'AYAR',
    'DURUM',
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
        CompactVoiceButton(controller: state.voice),
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
        if (state.callSimulator case final callSim?) ...[
          const SizedBox(height: 24),
          _IncomingCallSimulationSection(simulator: callSim, ringing: state.ringingCall),
        ],
        const SizedBox(height: 24),
        _PhoneBatterySimulationSection(state: state),
        const SizedBox(height: 24),
        _NavigationSimulationSection(state: state),
        const SizedBox(height: 24),
        _NotificationAccessSection(
          access: state.notificationAccess,
          permissions: state.permissions,
        ),
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
        OutlinedButton(
          onPressed: () => Future.delayed(
            const Duration(seconds: 5),
            () => _sim.injectButton(GlassesButton.tap),
          ),
          child: Semantics(
            label: '${Tr.delayedTap}. ${Tr.delayedTapHint}',
            excludeSemantics: true,
            child: const Text(Tr.delayedTap),
          ),
        ),
        const SizedBox(height: 8),
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
      ],
    );
  }
}

/// Telefon pilini taklit eder (Faz 7b): gerçek telefonu boşaltmadan düşük/kritik
/// pil uyarılarını, şarj olaylarını ve SOS sırasında ertelenmelerini dener.
/// Taklit, gerçek okumanın yerine geçer; "gerçek değere dön" ile kalkar.
class _PhoneBatterySimulationSection extends StatefulWidget {
  final AppState state;

  const _PhoneBatterySimulationSection({required this.state});

  @override
  State<_PhoneBatterySimulationSection> createState() => _PhoneBatterySimulationSectionState();
}

class _PhoneBatterySimulationSectionState extends State<_PhoneBatterySimulationSection> {
  late double _level = (widget.state.phoneBatteryPercent ?? 80).toDouble();
  late bool _charging = widget.state.phoneCharging ?? false;

  AppState get _state => widget.state;

  void _apply() {
    _state.phoneBatteryTest.force(PhoneBatteryReading(_level.round(), charging: _charging));
    _state.pollPhoneBattery();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.testPhoneBattery, style: Theme.of(context).textTheme.titleMedium),
        ),
        // Görsel başlık; TalkBack aynı bilgiyi kaydırıcının kendisinden duyar.
        ExcludeSemantics(
          child: Text(Tr.testPhoneBatteryPercent(_level.round()),
              style: Theme.of(context).textTheme.titleSmall),
        ),
        Slider(
          min: 0,
          max: 100,
          divisions: 20,
          value: _level,
          semanticFormatterCallback: (v) => Tr.testPhoneBatteryPercent(v.round()),
          onChanged: (v) => setState(() => _level = v),
          onChangeEnd: (_) => _apply(),
        ),
        SwitchListTile(
          title: const Text(Tr.testPhoneCharging),
          value: _charging,
          onChanged: (v) {
            setState(() => _charging = v);
            _apply();
          },
        ),
        OutlinedButton(
          onPressed: () {
            _state.phoneBatteryTest.clear();
            _state.pollPhoneBattery();
          },
          child: const Text(Tr.testPhoneBatteryReal),
        ),
      ],
    );
  }
}

/// Gelen aramayı (Faz 4b) `PatikaNotificationListener.kt` yazılmadan önce
/// taklit eder: arayan adını girip aramayı çaldırır, sonra gözlük
/// butonuyla (dokun = aç, uzun bas = reddet - bkz. `AppState._onButton`)
/// denenebilir.
class _IncomingCallSimulationSection extends StatefulWidget {
  final SimulatedCallService simulator;
  final IncomingCall? ringing;

  const _IncomingCallSimulationSection({required this.simulator, this.ringing});

  @override
  State<_IncomingCallSimulationSection> createState() => _IncomingCallSimulationSectionState();
}

class _IncomingCallSimulationSectionState extends State<_IncomingCallSimulationSection> {
  final _callerController = TextEditingController(text: 'Ahmet Yılmaz');

  @override
  void dispose() {
    _callerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringing = widget.ringing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.incomingCallSimulation, style: Theme.of(context).textTheme.titleMedium),
        ),
        Semantics(container: true, child: const Text(Tr.incomingCallSimulationHint)),
        const SizedBox(height: 12),
        TextField(
          controller: _callerController,
          decoration: const InputDecoration(
            labelText: Tr.callerNameLabel,
            hintText: Tr.callerNameHint,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            final name = _callerController.text.trim();
            if (name.isNotEmpty) widget.simulator.startCall(name);
          },
          icon: const Icon(Icons.phone_callback),
          label: const Text(Tr.startIncomingCall),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          child: Text(ringing == null ? Tr.noActiveCall : Tr.activeCall(ringing.callerName)),
        ),
      ],
    );
  }
}

/// Navigasyonu (Faz 6) gerçek konum olmadan dener: deneme rotasında "yürür",
/// rotadan sapar, konumu zayıflatır, karşıya geçiş duraklamasını sınar. Konum
/// kaynağı BLE simülasyonundan bağımsız ([AppState.simulatedLocation]).
class _NavigationSimulationSection extends StatefulWidget {
  final AppState state;

  const _NavigationSimulationSection({required this.state});

  @override
  State<_NavigationSimulationSection> createState() => _NavigationSimulationSectionState();
}

class _NavigationSimulationSectionState extends State<_NavigationSimulationSection> {
  RouteWalker? _walker;

  AppState get _state => widget.state;

  Future<void> _start() async {
    final route = demoRoute();
    final walker = RouteWalker(route);
    _walker = walker;
    _state.simulatedLocation.emit(walker.position);
    final result = await _state.navigation.start(route, location: _state.simulatedLocation);
    if (result == NavigationStart.started) {
      _state.feedback.say(describeRouteSummary(route,
          withDirectionNote: _state.navigation.announcesDirection));
    }
  }

  void _walk(double meters) {
    final walker = _walker;
    if (walker == null || !_state.navigation.active) return;
    walker.advance(meters);
    _state.simulatedLocation.emit(walker.position);
  }

  Future<void> _wander() async {
    final walker = _walker;
    if (walker == null || !_state.navigation.active) return;
    // Rota dışı için ardışık üç okuma gerekir (bkz. GuidanceConfig.offRouteFixes).
    for (var i = 0; i < 3; i++) {
      _state.simulatedLocation.emit(walker.offRoute(40));
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  void _backOnRoute() {
    final walker = _walker;
    if (walker == null || !_state.navigation.active) return;
    _state.simulatedLocation.emit(walker.position);
  }

  Future<void> _weakGps() async {
    final walker = _walker;
    if (walker == null || !_state.navigation.active) return;
    for (var i = 0; i < 3; i++) {
      _state.simulatedLocation.emit(walker.position, accuracy: 80);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state.navigation,
      builder: (context, _) {
        final nav = _state.navigation;
        final status = !nav.active
            ? Tr.testNavStatusIdle
            : nav.isPausedForCrossing
                ? Tr.testNavStatusPaused
                : nav.isOffRoute
                    ? Tr.testNavStatusOffRoute
                    : nav.isGpsWeak
                        ? Tr.testNavStatusWeakGps
                        : Tr.testNavStatusRunning;
        final remaining = nav.remainingText();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              container: true,
              child: Text(Tr.testNavTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            Semantics(container: true, child: const Text(Tr.testNavHint)),
            const SizedBox(height: 12),
            for (final (label, action) in [
              (Tr.testNavStart, _start),
              (Tr.testNavWalk10, () => _walk(10)),
              (Tr.testNavWalk50, () => _walk(50)),
              (Tr.testNavOffRoute, _wander),
              (Tr.testNavBackOnRoute, _backOnRoute),
              (Tr.testNavWeakGps, _weakGps),
              (Tr.testNavCrossed, () => nav.resumeFromCrossing()),
              (Tr.testNavStop, () => nav.stop()),
            ]) ...[
              OutlinedButton(onPressed: action, child: Text(label)),
              const SizedBox(height: 8),
            ],
            Semantics(container: true, child: Text(Tr.testNavStatus(status))),
            if (remaining != null) Semantics(container: true, child: Text(remaining)),
          ],
        );
      },
    );
  }
}

/// Bildirim dinleyici erişimini (Faz 4b, iskelet) dener: durumu gösterir,
/// kapalıysa sesli açıklamayla sistem ayar ekranını açar. Gerçek dinleyici
/// (`PatikaNotificationListener.kt`) henüz yok - yalnızca izin/kanal.
class _NotificationAccessSection extends StatefulWidget {
  final NotificationAccess access;
  final PermissionExplainer permissions;

  const _NotificationAccessSection({required this.access, required this.permissions});

  @override
  State<_NotificationAccessSection> createState() => _NotificationAccessSectionState();
}

class _NotificationAccessSectionState extends State<_NotificationAccessSection> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await widget.access.isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _request() async {
    await widget.permissions.ensureNotificationAccess(widget.access, Tr.notificationAccessWhy);
    // Ayarlar ayrı bir ekranda; kullanıcı geri dönünce durumu yeniden sorar.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          child: Text(Tr.notificationAccessTest, style: Theme.of(context).textTheme.titleMedium),
        ),
        Semantics(container: true, child: const Text(Tr.notificationAccessTestHint)),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          child: Text(enabled == null
              ? '...'
              : enabled
                  ? Tr.notificationAccessEnabled
                  : Tr.notificationAccessDisabled),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _refresh, child: const Text(Tr.checkNotificationAccess)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _request, child: const Text(Tr.requestNotificationAccess)),
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
        OutlinedButton.icon(
          onPressed: _runPriorityTest,
          icon: const Icon(Icons.low_priority),
          label: Semantics(
            label: Tr.priorityTestLabel,
            excludeSemantics: true,
            child: const Text(Tr.priorityTest),
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
