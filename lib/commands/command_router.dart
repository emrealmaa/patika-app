import '../ble/ble_command.dart';
import 'action_result.dart';
import 'intent.dart';
import 'handlers/call_handler.dart';
import 'handlers/crossing_mode_handler.dart';
import 'handlers/message_handler.dart';
import 'handlers/music_handler.dart';
import 'handlers/navigation_handler.dart';
import 'handlers/news_handler.dart';
import 'handlers/ocr_handler.dart';
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
  final MusicHandler _music;
  final NewsHandler _news;
  final TimeHandler _time;
  final WeatherHandler _weather;
  final OcrHandler _ocr;
  final CrossingModeHandler _crossingMode;
  final UnknownHandler _unknown;

  CommandRouter({
    CallHandler? call,
    MessageHandler? message,
    NavigationHandler? navigation,
    MusicHandler? music,
    NewsHandler? news,
    TimeHandler? time,
    WeatherHandler? weather,
    OcrHandler? ocr,
    CrossingModeHandler? crossingMode,
    UnknownHandler? unknown,
  })  : _call = call ?? CallHandler(),
        _message = message ?? MessageHandler(),
        _navigation = navigation ?? NavigationHandler(),
        _music = music ?? MusicHandler(),
        _news = news ?? NewsHandler(),
        _time = time ?? TimeHandler(),
        _weather = weather ?? WeatherHandler(),
        _ocr = ocr ?? OcrHandler(),
        _crossingMode = crossingMode ?? CrossingModeHandler(),
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
        case PatikaIntent.bilinmiyor:
          return await _unknown.handle(command.entity);
      }
    } catch (e) {
      return ActionResult.fail(
          '${command.intent.name}: beklenmeyen bir hata oluştu (${e.runtimeType})');
    }
  }
}
