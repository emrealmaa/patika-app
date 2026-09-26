import '../commands/action_result.dart';
import '../settings/settings.dart';
import 'announcement_queue.dart';
import 'earcons.dart';
import 'haptic_patterns.dart';

/// Anlamlı durum olayları - her biri bir titreşim deseni ve (varsa) kısa
/// sesle eşleşiyor.
enum FeedbackEvent {
  listening(HapticPatternId.listening, Earcon.listenStart),
  listenEnded(HapticPatternId.listening, Earcon.listenEnd),
  understood(HapticPatternId.understood, Earcon.listenEnd),
  notUnderstood(HapticPatternId.notUnderstood, Earcon.error),
  success(HapticPatternId.understood, Earcon.success),
  error(HapticPatternId.error, Earcon.error),
  connected(HapticPatternId.connected, null),
  disconnected(HapticPatternId.disconnected, null),
  batteryLow(HapticPatternId.batteryLow, null);

  final HapticPatternId haptic;
  final Earcon? earcon;
  const FeedbackEvent(this.haptic, this.earcon);
}

/// Kullanıcıya giden tüm geri bildirimin (ses + titreşim + kısa ses) tek
/// kapısı. Ekranlar ve AppState duyuru kuyruğunu, titreşimi ve kısa sesi
/// ayrı ayrı çağırmıyor - ayarlar (şiddet, bildirim türü, ayrıntı) burada
/// tek yerde uygulanıyor.
class FeedbackHub {
  final AnnouncementQueue queue;
  final HapticOutput haptics;
  final EarconPlayer earcons;
  final Settings Function() _settings;

  FeedbackHub({
    required this.queue,
    required this.haptics,
    required this.earcons,
    required Settings Function() settings,
  }) : _settings = settings;

  Settings get settings => _settings();

  /// Sadece konuşma (titreşim/kısa ses yok). Sonuna kadar okununca true,
  /// kesilince false ile tamamlanır.
  Future<bool> say(String text,
      {AnnouncementPriority priority = AnnouncementPriority.normal, bool dedupe = true}) {
    return queue.add(text, priority: priority, dedupe: dedupe);
  }

  /// Bir durum olayını bildirir.
  ///
  /// [text] içerik taşır ve her zaman okunur. [statusText] sadece durumu
  /// söyler ("Dinliyorum") - "sadece kısa ses" modunda ve olayın bir kısa
  /// sesi varsa okunmaz, kısa ses onun yerini tutar.
  void signal(
    FeedbackEvent event, {
    String? text,
    String? statusText,
    AnnouncementPriority priority = AnnouncementPriority.normal,
  }) {
    final s = settings;
    haptics.play(event.haptic, scale: s.hapticScale);
    final earcon = event.earcon;
    if (earcon != null) earcons.play(earcon);

    final skipStatus = s.feedbackMode == FeedbackMode.earconOnly && earcon != null;
    if (text != null) {
      queue.add(text, priority: priority);
    } else if (statusText != null && !skipStatus) {
      // Durum sözleri "tekrar et" ile tekrarlanmasın: kullanıcı son sonucu
      // duymak isterken "Dinliyorum" duymasın.
      queue.add(statusText, priority: priority, remember: false);
    }
  }

  /// Komut sonucunu sesle + titreşimle (+ kısa sesle) bildirir. Uzun ayrıntı
  /// modunda sonucun açıklaması da okunur.
  void result(ActionResult result) {
    if (result.handedOff) return;
    signal(
      result.success ? FeedbackEvent.success : FeedbackEvent.error,
      text: result.silent ? null : spokenResult(result, settings.verbosity),
    );
  }

  static String spokenResult(ActionResult result, Verbosity verbosity) {
    final detail = result.detail;
    if (verbosity == Verbosity.long && detail != null) {
      return '${result.message}. $detail';
    }
    return result.message;
  }

  void updateObstacle(double? distanceMeters) =>
      haptics.updateObstacle(distanceMeters, scale: settings.hapticScale);
}
