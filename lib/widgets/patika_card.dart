import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Uygulamanın ortak kartı: beyaz zemin, yuvarlak köşe, yumuşak indigo
/// gölge. [PatikaCard.hero] gradyanlı büyük kart (Konuş/Bağlantı üst kartı);
/// üstündeki yazı [PatikaTokens.onHero] olmalı.
///
/// Kart yalnızca görseldir, kendi anlamsal düğümü yoktur: içeriği TalkBack'e
/// olduğu gibi geçer. Hero'daki dekoratif daireler [ExcludeSemantics] içinde.
class PatikaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool _hero;

  const PatikaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PatikaTokens.gap),
  }) : _hero = false;

  const PatikaCard.hero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
  }) : _hero = true;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      _hero ? PatikaTokens.radiusHero : PatikaTokens.radiusCard,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hero ? null : PatikaTokens.card,
        gradient: _hero ? heroGradient : null,
        borderRadius: radius,
        boxShadow: _hero ? PatikaTokens.heroShadow : PatikaTokens.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        // Saydam Material: içerideki InkWell/düğme dalgaları kartın üstünde
        // çizilsin.
        child: Material(
          type: MaterialType.transparency,
          child: _hero
              ? Stack(
                  children: [
                    const Positioned.fill(child: ExcludeSemantics(child: HeroDecorations())),
                    Padding(padding: padding, child: child),
                  ],
                )
              : Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PatikaTokens.heroGradientStart, PatikaTokens.heroGradientEnd],
  );
}

/// Hero kartın köşelerindeki iki saydam daire (yalnızca süs).
class HeroDecorations extends StatelessWidget {
  const HeroDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(right: -50, top: -50, child: _Circle(size: 170, alpha: 0.07)),
        Positioned(left: -40, bottom: -60, child: _Circle(size: 150, alpha: 0.06)),
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double alpha;

  const _Circle({required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PatikaTokens.onHero.withValues(alpha: alpha),
      ),
    );
  }
}
