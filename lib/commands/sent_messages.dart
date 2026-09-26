import '../l10n/strings_tr.dart';
import '../l10n/turkish_suffix.dart';
import 'action_result.dart';

/// Son gönderilen/hazırlanan mesaj - yalnızca bellekte (uygulama kapanınca
/// kaybolur; mesaj içeriği diske yazılmaz).
class SentMessage {
  final String recipient;
  final String body;

  /// true: doğrudan gönderildi ve operatör onayladı ("direct" türü).
  /// false: SMS ekranı dolu açıldı; gönder tuşuna basılıp basılmadığı
  /// bilinmiyor ("play" türü) - kullanıcıya "gönderildi" DENMEZ.
  final bool confirmedSent;

  const SentMessage(this.recipient, this.body, {required this.confirmedSent});
}

class SentMessageLog {
  SentMessage? last;
}

/// SON_MESAJ: "gönderdiğim son mesajı oku".
class LastMessageHandler {
  final SentMessageLog _log;

  LastMessageHandler(this._log);

  Future<ActionResult> handle() async {
    final last = _log.last;
    if (last == null) return ActionResult.ok(Tr.lastSentNone);
    if (last.confirmedSent) {
      return ActionResult.ok(Tr.lastSent(dative(last.recipient), last.body));
    }
    return ActionResult.ok(Tr.lastPrepared(last.recipient, last.body),
        detail: Tr.lastPreparedDetail);
  }
}
