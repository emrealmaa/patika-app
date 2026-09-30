import 'dart:math' as math;

/// Standart yerçekimi (m/s²). Android ivmeölçeri m/s² verir; eşikler g ile.
const double standardGravity = 9.80665;

/// Tek ivmeölçer örneği. [tMs] sensörün monoton zamanı (ms; duvar saati
/// değil), eksenler m/s². Yalnızca bellekte yaşar: ham örnek hiçbir zaman
/// kayda yazılmaz (Faz 7c kararı 1).
class MotionSample {
  final int tMs;
  final double x;
  final double y;
  final double z;

  const MotionSample(this.tMs, this.x, this.y, this.z);

  /// İvme büyüklüğü, g cinsinden. Hareketsiz telefonda ~1, serbest düşüşte ~0.
  double get magnitudeG => math.sqrt(x * x + y * y + z * z) / standardGravity;
}
