import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accessibility/feedback_hub.dart';
import '../l10n/strings_tr.dart';

/// "Eğitim dinlendi mi" bilgisi. Ayarlardan AYRI tutuluyor: "Varsayılan
/// ayarlara dön" eğitimi bir sonraki açılışta yeniden başlatmasın.
abstract class TutorialProgress {
  Future<bool> isDone();
  Future<void> markDone();
}

class SharedPrefsTutorialProgress implements TutorialProgress {
  static const _key = 'patika.tutorialDone.v1';
  // İlk kullanımda oluşturuluyor (plugin yokken yapıcı hata fırlatıyor).
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> isDone() async {
    try {
      return await _prefs.getBool(_key) ?? false;
    } catch (e) {
      debugPrint('[Tutorial] okunamadı: $e');
      // Okunamıyorsa her açılışta eğitimle karşılamaktansa atla.
      return true;
    }
  }

  @override
  Future<void> markDone() async {
    try {
      await _prefs.setBool(_key, true);
    } catch (e) {
      debugPrint('[Tutorial] kaydedilemedi: $e');
    }
  }
}

class MemoryTutorialProgress implements TutorialProgress {
  bool done;

  MemoryTutorialProgress([this.done = false]);

  @override
  Future<bool> isDone() async => done;

  @override
  Future<void> markDone() async => done = true;
}

/// Sesli eğitim turu: gözlüğü bağlama, dinlemeyi başlatma, örnek ve
/// evrensel komutlar. İlk açılışta bir kez çalışır; "eğitimi başlat" ile
/// ya da Ayarlar'dan tekrar dinlenebilir.
///
/// Bir adım daha öncelikli bir duyuruyla ("Gözlük bağlandı") kesilirse o
/// adım tekrar okunur - kullanıcı bir adımı kaçırmaz. [stop] (dur komutu,
/// dinlemenin başlaması) turu hemen bitirir.
class Tutorial extends ChangeNotifier {
  /// Bir adım en fazla bu kadar kez kesilip tekrar okunur (sürekli kesen bir
  /// durum turu sonsuza kadar kilitlemesin).
  static const maxAttemptsPerStep = 3;
  static const stepPause = Duration(milliseconds: 500);

  final FeedbackHub _feedback;
  final TutorialProgress _progress;
  final List<String> steps;

  bool _running = false;
  int _run = 0;

  Tutorial(this._feedback, this._progress, {this.steps = Tr.tutorialSteps});

  bool get running => _running;

  /// İlk açılışta: daha önce dinlenmediyse başlatır.
  Future<void> startIfFirstRun() async {
    if (!await _progress.isDone()) await start();
  }

  /// Turu baştan başlatır; zaten sürüyorsa yeniden başlatır.
  Future<void> start() async {
    final run = ++_run;
    _running = true;
    notifyListeners();

    for (final step in steps) {
      var spoken = false;
      for (var attempt = 0; attempt < maxAttemptsPerStep && !spoken; attempt++) {
        spoken = await _feedback.say(step);
        if (run != _run) return; // durduruldu ya da yeniden başlatıldı
      }
      await Future.delayed(stepPause);
      if (run != _run) return;
    }

    await _progress.markDone();
    _running = false;
    notifyListeners();
    await _feedback.say(Tr.tutorialDone);
  }

  /// Turu hemen bitirir (konuşmayı susturmak çağıranın işi - genelde
  /// duyuru kuyruğu da aynı anda boşaltılıyor). Bilerek durdurulan tur da
  /// "dinlendi" sayılır: turun ilk cümlesi nasıl durdurulacağını söylüyor,
  /// durduran kullanıcı her açılışta yeniden dinlemek zorunda kalmasın
  /// ("eğitimi başlat" ile her zaman tekrar dinlenebilir).
  void stop() {
    if (!_running) return;
    _run++;
    _running = false;
    _progress.markDone();
    notifyListeners();
  }

  /// Uygulama kapanırken: turu keser ama "dinlendi" saymaz (kullanıcı
  /// durdurmadı), bekleyen döngü bir daha konuşmaz.
  @override
  void dispose() {
    _run++;
    _running = false;
    super.dispose();
  }
}
