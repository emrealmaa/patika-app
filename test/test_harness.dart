import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:patika_app/app_state.dart';
import 'package:patika_app/commands/contact_resolver.dart';
import 'package:patika_app/contacts/alias_store.dart';
import 'package:patika_app/contacts/contact_matcher.dart';
import 'package:patika_app/navigation/place_search.dart';
import 'package:patika_app/navigation/route_planner.dart';
import 'package:patika_app/platform/direct_actions.dart';
import 'package:patika_app/platform/incoming_messages.dart';
import 'package:patika_app/platform/location_service.dart';
import 'package:patika_app/platform/notification_access.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/settings/settings.dart';
import 'package:patika_app/settings/settings_store.dart';
import 'package:patika_app/sos/emergency_contacts.dart';
import 'package:patika_app/sos/emergency_number.dart';
import 'package:patika_app/sos/sos_call_monitor.dart';
import 'package:patika_app/tutorial/tutorial.dart';

import 'fakes.dart';

/// Platform eklentisi gerektirmeyen tam bir AppState: sahte TTS, konuşma
/// tanıma, titreşim, kısa ses; bellek içi ayar/cihaz/eğitim kaydı;
/// açılıştaki otomatik bağlanma kapalı.
/// Diyalog testleri için sahte rehber: iki Ahmet dahil.
const harnessContacts = [
  ContactEntry('1', 'Ahmet Yılmaz', ['0532 111 22 33']),
  ContactEntry('2', 'Ahmet Kaya', ['0533 444 55 66']),
  ContactEntry('3', 'Ayşe Demir', ['0534 777 88 99']),
  ContactEntry('6', 'Annem', ['0537 666 77 88']),
];

class _HarnessContacts implements ContactSource {
  final Completer<void>? Function() _gate;

  _HarnessContacts(this._gate);

  @override
  Future<List<ContactEntry>> loadAll() async {
    await _gate()?.future; // yavaş komut taklidi için (bkz. Harness.contactsGate)
    return harnessContacts;
  }
}

class Harness {
  final tts = FakeSpeechOutput();
  final speech = FakeSpeechInput();
  final haptics = FakeHaptics();
  final earcons = FakeEarcons();
  final tutorialProgress = MemoryTutorialProgress(true);
  final SettingsStore settings;
  bool micGranted = true;

  /// Doluysa rehber okuması bunu bekler: rehber kullanan bir komut (ör.
  /// NUMARA) tamamlanana dek "işleniyor" durumunda kalır.
  Completer<void>? contactsGate;

  /// Konum izni (varsayılan verilmiş) ve konum kaynağı: testte gerçek konum akmaz.
  final locationAccess = FakeLocationAccess(granted: true);
  final location = SimulatedLocationService();

  /// Uygulama ön planda mı (izin yokken yedek akışın kararı için).
  bool appVisible = true;

  /// Açılan tel:/sms: adresleri.
  final opened = <Uri>[];
  late final AppState app;

  /// Acil durum (Faz 7): kişiler bellekte, izinler verilmiş, arama sonu 40 sn.
  /// Test numarası dışında hiçbir şey aranamaz (bkz. FakeDirectActions).
  late final EmergencyContactStore emergencyContacts;
  final sosPermissions = FakeSosPermissions();
  final DirectActions directActions;

  /// Varsayılan "play" türü (doğrudan eylem yok); "direct" için sahte ver.
  Harness({
    Settings initial = const Settings(),
    DirectActions direct = const NoDirectActions(),
    IncomingMessages incomingMessages = const NoIncomingMessages(),
    LoudMessagesNotice? loudMessagesNotice,
    RoutePlanner? routePlanner,
    PlaceSearch? placeSearch,
    List<EmergencyContact> emergencyContacts = const [],
    SosCallMonitor? sosCallMonitor,
  })  : settings = SettingsStore(MemorySettingsPersistence()),
        directActions = direct {
    this.emergencyContacts = MemoryEmergencyContactStore(emergencyContacts);
    settings.update(initial);
    app = AppState(
      autoStart: false,
      speech: tts,
      speechInput: speech,
      haptics: haptics,
      earcons: earcons,
      settings: settings,
      deviceMemory: (_) => MemoryDeviceMemory(),
      ensureMicPermission: () async => micGranted,
      tutorialProgress: tutorialProgress,
      contacts: ContactResolver(
        source: _HarnessContacts(() => contactsGate),
        aliases: MemoryAliasStore(),
        ensurePermission: () async => true,
      ),
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
      direct: direct,
      ensureCallPermission: () async => true,
      ensureSmsPermission: () async => true,
      notificationAccess: const NoNotificationAccess(),
      incomingMessages: incomingMessages,
      loudMessagesNotice: loudMessagesNotice ?? MemoryLoudMessagesNotice(),
      locationAccess: locationAccess,
      locationService: location,
      routePlanner: routePlanner,
      placeSearch: placeSearch,
      isAppVisible: () => appVisible,
      emergencyContacts: this.emergencyContacts,
      sosPermissions: sosPermissions,
      emergencyNumber: const EmergencyNumber(debugTestNumber: '0999 000 00 00'),
      sosCallMonitor: sosCallMonitor ?? FakeCallMonitor(),
    );
  }

  /// Sıradaki tüm duyuruları "konuşulmuş" sayar (TTS bitti).
  void speakAll(FakeAsync async, {int max = 20}) {
    for (var i = 0; i < max; i++) {
      async.flushMicrotasks();
      tts.finishCurrent();
    }
    async.flushMicrotasks();
  }

  void dispose() => app.dispose();
}
