import 'announcement_queue.dart';
import 'feedback_hub.dart';

/// Widget olmayan her yerden (BuildContext gerektirmeden) sesli duyuru
/// yapmak için ince sarmalayıcı - asıl iş [FeedbackHub]/[AnnouncementQueue]
/// üzerinde. Duyurular TalkBack'e DEĞİL TTS'e gidiyor (TalkBack açıkken
/// çift okuma olmasın diye; TalkBack ekrandaki Semantics etiketlerini okur).
///
/// Hub henüz bağlanmadıysa (örn. testler) duyuru sessizce atlanır.
FeedbackHub? _hub;

void attachFeedbackHub(FeedbackHub? hub) => _hub = hub;

void announce(String message,
    {AnnouncementPriority priority = AnnouncementPriority.normal}) {
  _hub?.say(message, priority: priority);
}
