import 'announcement_queue.dart';
import 'feedback_hub.dart';

/// Konuşulmaması gereken anlarda (SOS'un başlattığı arama) duyuruyu bekleten
/// küçük yardımcı: yalnızca EN SON duyuru tutulur (eski durum bayattır),
/// [flush] yasak bitince söyler. Kuyruğun 3 sn birleştirmesi kapalıdır:
/// çağıran durum tekrarlarını zaten kendisi eler; açık olsaydı hızlı
/// "koptu -> bağlandı" dönüşünde ikinci "bağlandı" yutulur, kullanıcının
/// duyduğu son şey "koptu" kalırdı.
class HeldAnnouncer {
  final FeedbackHub _feedback;
  final bool Function() _hold;

  _Held? _held;

  HeldAnnouncer(this._feedback, {bool Function()? hold}) : _hold = hold ?? _never;

  static bool _never() => false;

  void announce(String text,
      {FeedbackEvent? event, AnnouncementPriority priority = AnnouncementPriority.normal}) {
    if (_hold()) {
      _held = _Held(event, text, priority);
      return;
    }
    if (event != null) _feedback.signal(event);
    _feedback.say(text, priority: priority, dedupe: false);
  }

  /// Yasak bittiyse bekleyen son duyuruyu söyler.
  void flush() {
    final held = _held;
    if (held == null || _hold()) return;
    _held = null;
    announce(held.text, event: held.event, priority: held.priority);
  }
}

class _Held {
  final FeedbackEvent? event;
  final String text;
  final AnnouncementPriority priority;

  const _Held(this.event, this.text, this.priority);
}
