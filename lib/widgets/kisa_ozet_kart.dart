import 'package:flutter/material.dart';

import '../l10n/strings_tr.dart';
import '../theme/app_theme.dart';
import 'patika_card.dart';

/// Uzun metin çözümü: kart tek cümlelik [summary] gösterir, ayrıntı
/// "Ayrıntıyı göster/gizle" düğmesiyle açılır/kapanır.
///
/// TalkBack sırası: başlık, özet, (açıksa) ayrıntı, düğme - önce özet
/// okunur. Düğmenin etiketi içinde (dışarıdan sarılmıyor: dokunma eylemi
/// kaybolmasın), "genişletildi/daraltıldı" durumu [Semantics.expanded] ile
/// bildirilir. Düğme ikincil: en az [PatikaTokens.minTouchSecondary].
///
/// Sonucu olan bilgi (ör. 112 ceza uyarısı) ayrıntıya saklanmaz, özette
/// kalır.
class KisaOzetKart extends StatefulWidget {
  final String? title;
  final String summary;

  /// Ayrıntı: düz metin ya da madde listesi (her öğe bir madde).
  final List<String> details;
  final bool initiallyExpanded;

  /// false: kendi kartını çizmez (başka bir kartın içine yerleştirmek için).
  final bool card;

  const KisaOzetKart({
    super.key,
    this.title,
    required this.summary,
    required this.details,
    this.initiallyExpanded = false,
    this.card = true,
  });

  @override
  State<KisaOzetKart> createState() => _KisaOzetKartState();
}

class _KisaOzetKartState extends State<KisaOzetKart> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = widget.title;
    final details = widget.details;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Semantics(header: true, child: Text(title, style: text.titleSmall)),
        if (title != null) const SizedBox(height: 4),
        Text(
          widget.summary,
          style: text.bodyMedium?.copyWith(color: PatikaTokens.textSecondary),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: PatikaTokens.gapSmall),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PatikaTokens.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in details)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: details.length == 1
                        ? Text(line, style: text.bodyMedium)
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(child: Text('•  ', style: text.bodyMedium)),
                              Expanded(child: Text(line, style: text.bodyMedium)),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          child: Semantics(
            label: Tr.detailToggleLabel(title, _expanded),
            expanded: _expanded,
            excludeSemantics: true,
            child: Text(_expanded ? Tr.detailHide : Tr.detailShow),
          ),
        ),
      ],
    );

    return widget.card ? PatikaCard(child: content) : content;
  }
}
