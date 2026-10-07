import 'package:flutter/material.dart';

/// Ekranın başlığı ("Patika", "Bağlantı", "Ayarlar"). Üst çubuk yok; her
/// ekran kendi başlığıyla başlar. TalkBack'te başlık (header) olarak
/// bildirilir ve ekranın ilk odağıdır.
class EkranBasligi extends StatelessWidget {
  final String text;

  /// Başlığın sağında (ör. Konuş'ta gözlük durumu hapı).
  final Widget? trailing;

  const EkranBasligi(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
    );
    final trailing = this.trailing;
    if (trailing == null) return title;
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        Flexible(child: trailing),
      ],
    );
  }
}
