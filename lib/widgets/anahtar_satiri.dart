import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Açma/kapama satırı: (varsa) ikon kutusu + başlık + (varsa) kısa alt yazı
/// + anahtar. Satırın tamamı dokunulabilir, en az [PatikaTokens.minTouch].
///
/// [SwitchListTile] üstüne kurulu: TalkBack satırı tek düğüm olarak,
/// "açık/kapalı" (toggled) durumuyla okur; durum yalnızca anahtarın
/// renginden anlaşılmaz.
class AnahtarSatiri extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  /// İkon kutusu SOS renklerinde (ör. 112 satırı).
  final bool danger;

  const AnahtarSatiri({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      minTileHeight: PatikaTokens.minTouch,
      contentPadding: EdgeInsets.zero,
      secondary: icon == null
          ? null
          : ExcludeSemantics(
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
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}
