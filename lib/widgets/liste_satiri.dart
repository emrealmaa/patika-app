import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Kart içindeki satır: ikon kutusu + başlık + (varsa) alt yazı + (varsa)
/// sağda değer ya da ok. En az [PatikaTokens.minTouch] yüksekliğinde.
///
/// TalkBack satırı tek parça okur ([semanticLabel] verilmişse onu, yoksa
/// başlık ve alt yazıyı). İkon ve ok süstür, okunmaz. [onTap] verilirse
/// satır düğme olarak bildirilir ve çift dokunuşla tetiklenir.
class ListeSatiri extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;

  /// Sağda kısa değer ("%78"). Okunuşu [semanticLabel]'a yazılmalı.
  final String? value;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// İkon kutusu SOS renklerinde (ör. 112 satırı).
  final bool danger;

  /// Satırın altında ince ayraç (kart içinde ardışık satırlar için).
  final bool divider;

  const ListeSatiri({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.semanticLabel,
    this.danger = false,
    this.divider = false,
  });

  String get _spoken => semanticLabel ?? [title, ?subtitle, ?value].join(', ');

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: PatikaTokens.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: danger ? PatikaTokens.sosSurface : PatikaTokens.primarySoft,
                    borderRadius: BorderRadius.circular(PatikaTokens.radiusIconBox),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: danger ? PatikaTokens.sos : PatikaTokens.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PatikaTokens.textSecondary),
                    ),
                ],
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: PatikaTokens.primary),
              ),
            if (onTap != null)
              const ExcludeSemantics(
                child: Icon(Icons.chevron_right, color: PatikaTokens.textSecondary),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: _spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: divider
              ? const Border(bottom: BorderSide(color: PatikaTokens.divider))
              : null,
        ),
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
