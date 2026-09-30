import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fall_detector.dart';

/// Gölge kaydının tek satırı (Faz 7c). **Yalnızca** zaman, kaynak, sonuç ve
/// özet değerler: konum ve ham sensör örneği bu sınıfta hiç yok (Faz 7c kararı
/// 1; alan listesi `fall_shadow_log_test.dart`'ta kilitli).
class FallShadowRecord {
  /// Değerlendirmenin bittiği an (duvar saati).
  final DateTime at;

  /// Aday kaynağı (`FallCandidateSource.sourceId`, ör. `phone_imu`).
  final String source;
  final FallOutcome outcome;
  final int freeFallMs;
  final double peakG;
  final double? orientationDegrees;
  final double? stillnessStdG;

  const FallShadowRecord({
    required this.at,
    required this.source,
    required this.outcome,
    required this.freeFallMs,
    required this.peakG,
    this.orientationDegrees,
    this.stillnessStdG,
  });

  factory FallShadowRecord.fromEvaluation(FallEvaluation e, {required DateTime at, required String source}) =>
      FallShadowRecord(
        at: at,
        source: source,
        outcome: e.outcome,
        freeFallMs: e.freeFallMs,
        peakG: e.peakG,
        orientationDegrees: e.orientationDegrees,
        stillnessStdG: e.stillnessStdG,
      );

  /// Kısa anahtarlar: 200 kayıtlık dosya küçük kalsın. Değerler yuvarlanır
  /// (ölçüm hassasiyetinden fazlası yalnızca yer kaplar).
  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'src': source,
        'out': outcome.name,
        'ffMs': freeFallMs,
        'peakG': _round(peakG, 2),
        'deg': orientationDegrees == null ? null : _round(orientationDegrees!, 1),
        'std': stillnessStdG == null ? null : _round(stillnessStdG!, 3),
      };

  /// Bozuk ya da tanınmayan satır için null (atlanır, uygulama durmaz).
  static FallShadowRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final src = json['src'];
    final out = FallOutcome.values.asNameMap()[json['out']];
    final ff = json['ffMs'];
    final peak = json['peakG'];
    final deg = json['deg'];
    final std = json['std'];
    if (at is! int || src is! String || out == null || ff is! int || peak is! num) return null;
    if (deg != null && deg is! num) return null;
    if (std != null && std is! num) return null;
    return FallShadowRecord(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      source: src,
      outcome: out,
      freeFallMs: ff,
      peakG: peak.toDouble(),
      orientationDegrees: (deg as num?)?.toDouble(),
      stillnessStdG: (std as num?)?.toDouble(),
    );
  }

  static double _round(double v, int digits) => double.parse(v.toStringAsFixed(digits));
}

/// Gölge kaydının saklandığı yer. Gerçeği `FallShadowLogStorage.kt`
/// (`noBackupFilesDir`, yedeğe girmez); testte bellek.
abstract class FallLogStore {
  /// Kayıtlı JSON metni; yoksa null.
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

/// Gerçek depo: kanal `patika/fall_log`.
class MethodChannelFallLogStore implements FallLogStore {
  static const _channel = MethodChannel('patika/fall_log');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> write(String json) => _channel.invokeMethod<void>('write', {'json': json});

  @override
  Future<void> clear() => _channel.invokeMethod<void>('clear');
}

/// Bellekte depo (testler ve native kanalı olmayan ortam).
class MemoryFallLogStore implements FallLogStore {
  String? content;
  int writes = 0;

  /// true iken yazma hata fırlatır (depo hatası testi).
  bool failWrites = false;

  MemoryFallLogStore([this.content]);

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String json) async {
    if (failWrites) throw PlatformException(code: 'write_failed');
    writes++;
    content = json;
  }

  @override
  Future<void> clear() async => content = null;
}

/// Düşme algılamanın gölge kaydı (Faz 7c-1). Kalıcıdır; en fazla
/// [maxRecords] kayıt ve [maxAge] gün tutar (hangisi önce dolarsa, eskiler
/// atılır). Yalnızca **darbe adımına ulaşan** değerlendirmeler girer;
/// `noImpact` sayılır ama yazılmaz (bkz. `FallMonitor`).
///
/// Depo hatası uygulamayı durdurmaz: okunamazsa boş liste, yazılamazsa kayıt
/// bellekte kalır (bir sonraki yazmada yeniden denenir).
/// İşlemler sırayla yürür: art arda gelen eklemeler birbirini ezmez.
class FallShadowLog extends ChangeNotifier {
  static const maxRecords = 200;
  static const maxAge = Duration(days: 14);

  final FallLogStore _store;
  final DateTime Function() _now;
  final _records = <FallShadowRecord>[];
  Future<void> _tail = Future.value();
  bool _loaded = false;

  FallShadowLog(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Eskiden yeniye.
  List<FallShadowRecord> get records => List.unmodifiable(_records);

  /// Depodan yükler (budar; budama bir şey attıysa geri yazar). İlk
  /// [add]/[clear] de gerekirse kendiliğinden yükler.
  Future<void> load() => _serial(_ensureLoaded);

  /// Değerlendirmeyi kaydeder. Darbe adımına ulaşmadıysa yazmaz, false döner.
  Future<bool> add(FallEvaluation e, {required String source}) {
    if (!e.outcome.reachedImpact) return Future.value(false);
    return _serial(() async {
      await _ensureLoaded();
      _records.add(FallShadowRecord.fromEvaluation(e, at: _now(), source: source));
      _prune();
      await _persist();
      notifyListeners();
      return true;
    });
  }

  /// Tüm kaydı siler (Test Modu "Kayıtları sil").
  Future<void> clear() => _serial(() async {
        _loaded = true;
        _records.clear();
        try {
          await _store.clear();
        } catch (e) {
          debugPrint('[Düşme] kayıt silinemedi: ${e.runtimeType}');
        }
        notifyListeners();
      });

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _store.read();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _records.addAll([for (final j in decoded) ?FallShadowRecord.fromJson(j)]);
        }
      }
    } catch (e) {
      debugPrint('[Düşme] kayıt okunamadı: ${e.runtimeType}');
    }
    if (_prune()) await _persist();
    notifyListeners();
  }

  /// Süresi geçenleri ve sınırın üstündekileri (en eskiden) atar.
  bool _prune() {
    final before = _records.length;
    final cutoff = _now().subtract(maxAge);
    _records.removeWhere((r) => r.at.isBefore(cutoff));
    if (_records.length > maxRecords) {
      _records.removeRange(0, _records.length - maxRecords);
    }
    return _records.length != before;
  }

  Future<void> _persist() async {
    try {
      await _store.write(jsonEncode([for (final r in _records) r.toJson()]));
    } catch (e) {
      debugPrint('[Düşme] kayıt yazılamadı: ${e.runtimeType}');
    }
  }
}
