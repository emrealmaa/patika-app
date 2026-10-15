/// Mesajın gideceği uygulama. Sesli komutta "WhatsApp" geçerse WhatsApp;
/// geçmezse Ayarlar'daki varsayılan ([Settings.messageApp]).
enum MessageApp { sms, whatsapp }

/// Rehber numarasını WhatsApp'ın beklediği uluslararası biçime çevirir
/// (yalnızca rakam, ülke kodu dahil, `+` ve baştaki `00` yok). Ülke kodu
/// olmayan Türkiye numaraları: `0532...` (11 hane) ve `532...` (10 hane)
/// başına 90 alır. Rakam yoksa null.
String? whatsappNumber(String raw) {
  final hasPlus = raw.trim().startsWith('+');
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (hasPlus) return digits;
  if (digits.startsWith('00')) return digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) return '90${digits.substring(1)}';
  if (digits.length == 10 && digits.startsWith('5')) return '90$digits';
  return digits;
}
