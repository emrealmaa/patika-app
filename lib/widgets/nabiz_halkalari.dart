import 'package:flutter/material.dart';

/// Dışa doğru büyüyüp sönen iki halka (Konuş: dinleme nabzı, Bağlantı:
/// tarama dalgası). Yalnızca süs: tamamı [ExcludeSemantics] içinde, anlamsal
/// etiketleri ve odak sırasını değiştirmez.
///
/// Ömür: yalnızca ilgili durum sürerken ağaca konur (dinlerken, tararken);
/// durum bitince ağaçtan çıkar ve denetleyici [dispose] edilir. Görünmeyen
/// bir yerdeyse ([TickerMode] kapalı, ör. SOS ekranının arkası) ticker
/// susturulur. "Hareketi azalt" açıkken ([MediaQuery.disableAnimationsOf])
/// denetleyici hiç çalışmaz, halkalar durağan çizilir.
class NabizHalkalari extends StatefulWidget {
  /// Halkanın taban çapı.
  final double size;
  final Color color;

  /// Halkanın başlangıç ve bitiş ölçeği (taban çapa göre).
  final double minScale;
  final double maxScale;

  /// Halkanın başlangıçtaki saydamlığı (sönerek 0'a iner).
  final double opacity;
  final Duration period;

  const NabizHalkalari({
    super.key,
    required this.size,
    required this.color,
    this.minScale = 1.0,
    this.maxScale = 1.6,
    this.opacity = 0.45,
    this.period = const Duration(milliseconds: 2400),
  });

  @override
  State<NabizHalkalari> createState() => _NabizHalkalariState();
}

class _NabizHalkalariState extends State<NabizHalkalari> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Faz [t] (0..1) için bir halka.
  Widget _ring(double t) {
    final scale = widget.minScale + (widget.maxScale - widget.minScale) * t;
    return Container(
      width: widget.size * scale,
      height: widget.size * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withValues(alpha: widget.opacity * (1 - t)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * widget.maxScale;
    return ExcludeSemantics(
      child: SizedBox(
        width: box,
        height: box,
        child: _reduceMotion
            // Durağan: iki sabit halka (dinleme/tarama sürdüğü yine görülür).
            ? Stack(alignment: Alignment.center, children: [_ring(0.6), _ring(0.25)])
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [_ring(t), _ring((t + 0.5) % 1)],
                  );
                },
              ),
      ),
    );
  }
}
