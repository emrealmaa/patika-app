import '../../l10n/strings_tr.dart';
import '../../l10n/turkish_suffix.dart';
import '../action_result.dart';
import '../incoming_message_log.dart';

/// MESAJLARIM ve SON_BİLDİRİMLER niyetleri (Faz 4b) - ikisi de bildirimden
/// yakalanan mesajların aynı [IncomingMessageLog]'unu okur, farklı amaçla:
/// [readNew] içerik odaklı ("ne yazmışlar"), [readRecent] özet odaklı
/// ("kim aramış/yazmış").
class MessageHistoryHandler {
  final IncomingMessageLog _log;

  MessageHistoryHandler(this._log);

  /// "mesajlarımı oku": henüz okunmamış mesajları eskiden yeniye, tam
  /// içerikleriyle okur ve okunmuş sayar.
  Future<ActionResult> readNew() async {
    final unread = _log.takeUnread();
    if (unread.isEmpty) return ActionResult.ok(Tr.noNewMessages);
    return ActionResult.ok(Tr.newMessages([
      for (final m in unread) Tr.incomingMessage(ablative(m.senderName), m.body),
    ]));
  }

  /// "son bildirimleri oku": en fazla 20 bildirimin yalnızca göndereni,
  /// yeniden eskiye - okunmuş/okunmamış durumunu etkilemez.
  Future<ActionResult> readRecent() async {
    final recent = _log.recent();
    if (recent.isEmpty) return ActionResult.ok(Tr.noRecentNotifications);
    return ActionResult.ok(
        Tr.recentNotifications([for (final m in recent) ablative(m.senderName)]));
  }
}
