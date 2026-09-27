import '../platform/incoming_messages.dart';

/// Bildirimden yakalanan mesajların bellekteki günlüğü (Faz 4b) - yalnızca
/// bellekte, en fazla [maxEntries] tutulur, en eskisi atılır. "Bildirimleri
/// sustur" açıkken de mesajlar buraya eklenmeye devam eder - yalnızca
/// duyuru susturulur, kayıt değil (bkz. CLAUDE.md karar 4).
class IncomingMessageLog {
  static const maxEntries = 20;

  /// Eskiden yeniye.
  final _entries = <_Entry>[];

  void add(IncomingMessage message) {
    _entries.add(_Entry(message));
    if (_entries.length > maxEntries) _entries.removeAt(0);
  }

  /// "mesajlarımı oku": henüz bu komutla okunmamışlar, eskiden yeniye (doğal
  /// okuma sırası). Çağrıldıktan sonra hepsi okunmuş sayılır.
  List<IncomingMessage> takeUnread() {
    final unread = [for (final e in _entries) if (!e.read) e.message];
    for (final e in _entries) {
      e.read = true;
    }
    return unread;
  }

  /// "son bildirimleri oku": en fazla [maxEntries] mesaj, yeniden eskiye -
  /// okunmuş/okunmamış ayrımı yok, [takeUnread]'i etkilemez.
  List<IncomingMessage> recent() => [for (final e in _entries.reversed) e.message];
}

class _Entry {
  final IncomingMessage message;
  bool read = false;
  _Entry(this.message);
}
