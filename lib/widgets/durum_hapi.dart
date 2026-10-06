import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Durum hapı: renkli nokta + yazı ("Gözlük bağlı").
///
/// Bilgi yalnızca renkle verilmez: anlam her zaman yazıda, nokta yardımcı
/// işarettir ve [ExcludeSemantics] içindedir. TalkBack yalnızca yazıyı
/// (ya da verilmişse [semanticLabel]'ı) tek parça okur.
class DurumHapi extends StatelessWidget {
  final String text;
  final Color dotColor;
  final Color textColor;

  /// Ekrandaki kısa yazıdan farklı okunması gerekiyorsa (ör. "%78" yerine
  /// "yüzde 78").
  final String? semanticLabel;

  const DurumHapi({
    super.key,
    required this.text,
    required this.dotColor,
    required this.textColor,
    this.semanticLabel,
  });

  /// Olumlu durum: "Gözlük bağlı".
  const DurumHapi.basari(this.text, {super.key, this.semanticLabel})
      : dotColor = PatikaTokens.successDot,
        textColor = PatikaTokens.successText;

  /// Nötr durum: "Gözlük bağlı değil".
  const DurumHapi.notr(this.text, {super.key, this.semanticLabel})
      : dotColor = PatikaTokens.neutralDot,
        textColor = PatikaTokens.textSecondary;

  /// Uyarı durumu: "Pil düşük".
  const DurumHapi.uyari(this.text, {super.key, this.semanticLabel})
      : dotColor = PatikaTokens.sos,
        textColor = PatikaTokens.sos;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel ?? text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PatikaTokens.card,
          borderRadius: BorderRadius.circular(PatikaTokens.radiusPill),
          boxShadow: PatikaTokens.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: PatikaTokens.gapSmall),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
