import 'package:flutter/foundation.dart';

import '../ble/ble_command.dart';
import '../l10n/strings_tr.dart';
import '../settings/settings_store.dart';
import 'action_result.dart';
import '../sos/emergency_contacts.dart';
import 'incoming_message_log.dart';
import 'intent.dart';
import 'sent_messages.dart';
import 'handlers/alias_handler.dart';
import 'handlers/call_handler.dart';
import 'handlers/control_handler.dart';
import 'handlers/crossing_mode_handler.dart';
import 'handlers/emergency_contact_handler.dart';
import 'handlers/message_handler.dart';
import 'handlers/message_history_handler.dart';
import 'handlers/navigation_control_handler.dart';
import 'handlers/music_handler.dart';
import 'handlers/navigation_handler.dart';
import 'handlers/news_handler.dart';
import 'handlers/number_handler.dart';
import 'handlers/ocr_handler.dart';
import 'handlers/settings_handler.dart';
import 'handlers/time_handler.dart';
import 'handlers/unknown_handler.dart';
import 'handlers/weather_handler.dart';

/// Gözlükten (gerçek BLE ya da simülasyon) gelen [BleCommand]'i doğru
/// handler'a yönlendiren tek giriş noktası - Python tarafındaki
/// phone_bridge.isle()'nin gerçek Flutter karşılığı. Çağıranlar (main.py'nin
/// Flutter'daki karşılığı - main.dart/screens) hep bunu kullanmalı, tek tek
/// handler'ları değil.
class CommandRouter {
  final CallHandler _call;
  final MessageHandler _message;
  final NavigationHandler _navigation;
  final NavigationControlHandler _navigationControl;
  final MusicHandler _music;
  final NewsHandler _news;
  final TimeHandler _time;
  final WeatherHandler _weather;
  final OcrHandler _ocr;
  final CrossingModeHandler _crossingMode;
  final SettingsHandler _settings;
  final ControlHandler _control;
  final NumberHandler _number;
  final AliasHandler _alias;
  final LastMessageHandler _lastMessage;
  final MessageHistoryHandler _messageHistory;
  final EmergencyContactHandler _emergencyContact;
  final UnknownHandler _unknown;

  CommandRouter({
    CallHandler? call,
    MessageHandler? message,
    NavigationHandler? navigation,
    NavigationControlHandler? navigationControl,
    MusicHandler? music,
    NewsHandler? news,
    TimeHandler? time,
    WeatherHandler? weather,
    OcrHandler? ocr,
    CrossingModeHandler? crossingMode,
    SettingsHandler? settings,
    ControlHandler? control,
    NumberHandler? number,
    AliasHandler? alias,
    LastMessageHandler? lastMessage,
    MessageHistoryHandler? messageHistory,
    EmergencyContactHandler? emergencyContact,
    UnknownHandler? unknown,
  })  : _call = call ?? CallHandler(),
        _message = message ?? MessageHandler(),
        _navigation = navigation ?? NavigationHandler(),
        _navigationControl = navigationControl ?? NavigationControlHandler(),
        _music = music ?? MusicHandler(),
        _news = news ?? NewsHandler(),
        _time = time ?? TimeHandler(),
        _weather = weather ?? WeatherHandler(),
        _ocr = ocr ?? OcrHandler(),
        _crossingMode = crossingMode ?? CrossingModeHandler(),
        _settings = settings ??
            SettingsHandler(SettingsStore(MemorySettingsPersistence())),
        _control = control ?? ControlHandler(),
        _number = number ?? NumberHandler(),
        _alias = alias ?? AliasHandler(),
        _lastMessage = lastMessage ?? LastMessageHandler(SentMessageLog()),
        _messageHistory = messageHistory ?? MessageHistoryHandler(IncomingMessageLog()),
        _emergencyContact =
            emergencyContact ?? EmergencyContactHandler(store: MemoryEmergencyContactStore()),
        _unknown = unknown ?? UnknownHandler();

  /// Handler'lardan biri beklenmedik bir istisna fırlatırsa (örn. rehber/BLE
  /// plugin'i platform hatası - MissingPluginException, PlatformException vb.)
  /// bunu burada tek noktadan yakalayıp bilgilendirici bir [ActionResult.fail]
  /// döndürür. Python tarafındaki "asla çökmesin" ilkesiyle aynı ruh (bkz.
  /// patika/NOTES.md, intent_classifier.py'nin Gemini fallback'i) - bir
  /// komutun işlenmesi asla uygulamayı ya da komut akışını kilitlememeli.
  Future<ActionResult> route(BleCommand command) async {
    try {
      switch (command.intent) {
        case PatikaIntent.ara:
          return await _call.handle(command.entity);
        case PatikaIntent.mesaj:
          return await _message.handle(command.entity);
        case PatikaIntent.navigasyon:
          return await _navigation.handle(command.entity);
        case PatikaIntent.muzik:
          return await _music.handle(command.entity);
        case PatikaIntent.haber:
          return await _news.handle(command.entity);
        case PatikaIntent.saat:
          return await _time.handle(command.entity);
        case PatikaIntent.hava:
          return await _weather.handle(command.entity);
        case PatikaIntent.oku:
          return await _ocr.handle(command.entity);
        case PatikaIntent.gecisModu:
          return await _crossingMode.handle(command.entity);
        case PatikaIntent.ayar:
          return await _settings.handle(command.entity);
        case PatikaIntent.numara:
          return await _number.handle(command.entity);
        case PatikaIntent.takmaAd:
          return await _alias.handle(command.entity);
        case PatikaIntent.sonMesaj:
          return await _lastMessage.handle();
        case PatikaIntent.mesajlarim:
          return await _messageHistory.readNew();
        case PatikaIntent.sonBildirimler:
          return await _messageHistory.readRecent();
        case PatikaIntent.navigasyonBitir:
          return await _navigationControl.stop();
        case PatikaIntent.navigasyonKalan:
          return await _navigationControl.remaining();
        case PatikaIntent.gectim:
          return await _navigationControl.crossed();
        case PatikaIntent.acilKisi:
          return await _emergencyContact.handle(command.entity);
        case PatikaIntent.dur:
        case PatikaIntent.tekrar:
        case PatikaIntent.komutlar:
        case PatikaIntent.egitim:
        case PatikaIntent.sos:
          return await _control.handle(command.intent);
        case PatikaIntent.bilinmiyor:
          return await _unknown.handle(command.entity);
      }
    } catch (e) {
      debugPrint('[CommandRouter] ${command.intent.name} başarısız: $e');
      return ActionResult.fail(Tr.unexpectedError);
    }
  }
}
