import '../l10n/strings_tr.dart';
import '../navigation/geo.dart';
import '../navigation/guidance_engine.dart' show PositionFix;

/// Acil kişilere giden SMS metinleri. Konum bir Google Haritalar bağlantısı
/// olarak gider (alıcı uygulama kurmadan açabilir).
abstract final class SosMessage {
  static String mapsLink(LatLng p) =>
      'https://maps.google.com/?q=${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';

  /// İlk mesaj. [fix] yoksa "Konum alınamadı" der (takip SMS'i gelebilir).
  static String initial({required DateTime time, PositionFix? fix}) {
    final head = Tr.sosSmsInitial(_hhmm(time));
    if (fix == null) return '$head ${Tr.sosSmsNoLocation}';
    return '$head ${Tr.sosSmsLocation(mapsLink(fix.position), _accuracy(fix))}';
  }

  /// Konum sonradan bulunduysa atılan TEK takip mesajı.
  static String followUp({required DateTime time, required PositionFix fix}) =>
      Tr.sosSmsFollowUp(_hhmm(time), mapsLink(fix.position), _accuracy(fix));

  static int _accuracy(PositionFix fix) => fix.accuracyMeters.isFinite ? fix.accuracyMeters.round() : 0;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
