import '../l10n/strings_tr.dart';
import 'fall_open_gate.dart';

/// Kapının tutmama nedeni metni: ses diyaloğu ve ekran (Ayarlar düğmesi)
/// AYNI metni kullanır (plan §5: her kanalda aynı metin).
String fallOpenBlockText(FallOpenGateResult gate) => switch (gate.block) {
      FallOpenBlock.unsupportedBuild => Tr.fallOpenBlockedBuild,
      FallOpenBlock.noContacts => Tr.fallOpenBlockedNoContacts,
      FallOpenBlock.noSmsPermission => Tr.fallOpenBlockedNoSms,
      FallOpenBlock.shadowTooShort => Tr.fallOpenBlockedShadow(gate.daysLeft ?? 7),
      null => Tr.fallOpenNotEnabled,
    };
