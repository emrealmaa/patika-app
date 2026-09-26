import 'dart:async';

import 'speech_output.dart';

/// Duyuru öncelikleri - sıralama önemli (index büyüdükçe öncelik artar).
enum AnnouncementPriority {
  /// Bilgi amaçlı; sırada fazla beklerse atılır.
  low,

  /// Komut sonuçları.
  normal,

  /// Bağlantı değişimi, gelen arama.
  high,

  /// Engel, SOS.
  critical,
}

class Announcement {
  final String text;
  final AnnouncementPriority priority;
  final DateTime createdAt;

  /// false: "tekrar et" için hatırlanmaz (örn. "Dinliyorum" gibi durum sözleri).
  final bool remember;
  final _done = Completer<bool>();

  Announcement(this.text, this.priority, this.createdAt, {this.remember = true});

  /// Konuşma sonuna kadar okununca true, kesilince/atılınca false ile
  /// tamamlanır.
  Future<bool> get done => _done.future;

  void _finish(bool spokenFully) {
    if (!_done.isCompleted) _done.complete(spokenFully);
  }
}

/// Tüm sesli duyuruların geçtiği tek kuyruk.
///
/// - Daha yüksek öncelikli bir duyuru o an konuşulanı KESER. Kesilen
///   duyuru tekrar sıraya alınmaz (kullanıcı "tekrar et" diyebilir -
///   [lastSpoken]); aksi halde engel uyarısından sonra eski bilgi
///   araya girerdi.
/// - Aynı metin konuşulurken/sıradayken ya da [dedupeWindow] içinde
///   yeniden gelirse birleştirilir (tekrar okunmaz). Kesilen duyuru bu
///   kurala takılmaz - sonuna kadar duyulmamıştı.
/// - [AnnouncementPriority.low] duyurular [lowMaxAge]'den uzun beklediyse
///   atılır - bayat bilgi okunmaz.
class AnnouncementQueue {
  final SpeechOutput _output;
  final Duration dedupeWindow;
  final Duration lowMaxAge;
  final DateTime Function() _now;

  final List<Announcement> _pending = [];
  final Map<String, DateTime> _recent = {};
  Announcement? _current;
  int _generation = 0;
  String? _lastSpoken;

  AnnouncementQueue(
    this._output, {
    this.dedupeWindow = const Duration(seconds: 3),
    this.lowMaxAge = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// En son konuşulmaya başlanan duyuru ("tekrar et" komutu için).
  String? get lastSpoken => _lastSpoken;

  /// Şu an konuşulan duyuru (yoksa null).
  Announcement? get current => _current;

  /// Dönen Future duyuru sonuna kadar okununca true, kesilince ya da
  /// (tekrar/bayat olduğu için) atılınca false ile tamamlanır - "önce
  /// açıkla, sonra sor" (PermissionExplainer) ve "kesilen adımı tekrarla"
  /// (Tutorial) akışları bunu bekliyor.
  ///
  /// [remember] false ise duyuru "tekrar et" ile tekrarlanacak son duyuru
  /// olarak hatırlanmaz.
  Future<bool> add(
    String text, {
    AnnouncementPriority priority = AnnouncementPriority.normal,
    bool remember = true,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isDuplicate(trimmed)) return Future.value(false);

    final item = Announcement(trimmed, priority, _now(), remember: remember);
    _insertByPriority(item);

    final current = _current;
    if (current != null && priority.index > current.priority.index) {
      _interrupt();
    } else {
      _pump();
    }
    return item.done;
  }

  /// Son duyuruyu tekrar okur (tekrar birleştirme kuralına takılmadan).
  /// Tekrar edilecek bir şey yoksa false döner.
  bool repeatLast() {
    final last = _lastSpoken;
    if (last == null) return false;
    _recent.remove(last);
    add(last);
    return true;
  }

  /// Konuşmayı keser ve sırayı boşaltır ("dur" komutu).
  void stopAll() {
    for (final a in _pending) {
      a._finish(false);
    }
    _pending.clear();
    final current = _current;
    if (current != null) {
      _generation++;
      _current = null;
      _forgetUnheard(current);
      current._finish(false);
      _output.stop();
    }
  }

  /// Kesilen duyuru kullanıcıya ulaşmadı: tekrar eklenirse (eğitimin
  /// kesilen adımı gibi) "yakında okundu" sayılıp atlanmasın.
  void _forgetUnheard(Announcement a) => _recent.remove(a.text);

  bool _isDuplicate(String text) {
    if (_current?.text == text) return true;
    if (_pending.any((a) => a.text == text)) return true;
    final now = _now();
    _recent.removeWhere((_, at) => now.difference(at) > dedupeWindow);
    return _recent.containsKey(text);
  }

  /// Önceliğe göre azalan, eşit öncelikte geliş sırasına göre ekler.
  void _insertByPriority(Announcement item) {
    final index = _pending.indexWhere((a) => a.priority.index < item.priority.index);
    if (index == -1) {
      _pending.add(item);
    } else {
      _pending.insert(index, item);
    }
  }

  void _interrupt() {
    _generation++;
    final current = _current;
    if (current != null) {
      _forgetUnheard(current);
      current._finish(false);
    }
    _current = null;
    _output.stop();
    _pump();
  }

  Future<void> _pump() async {
    if (_current != null) return;
    while (_pending.isNotEmpty) {
      final next = _pending.removeAt(0);
      final now = _now();
      if (next.priority == AnnouncementPriority.low &&
          now.difference(next.createdAt) > lowMaxAge) {
        next._finish(false);
        continue;
      }

      _current = next;
      if (next.remember) _lastSpoken = next.text;
      _recent[next.text] = now;
      final generation = ++_generation;

      try {
        await _output.speak(next.text);
      } catch (_) {
        // Seslendirme hatası kuyruğu asla kilitlememeli.
      }
      // Bu sırada kesildiyse _interrupt/stopAll zaten false ile bitirdi.
      next._finish(true);
      // Bu sırada daha öncelikli bir duyuru araya girdiyse, kuyruğu artık
      // o turun _pump'ı yürütüyor.
      if (generation != _generation) return;
      _current = null;
    }
  }
}
