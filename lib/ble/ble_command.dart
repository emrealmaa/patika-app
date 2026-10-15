import '../commands/intent.dart';
import '../commands/message_app.dart';

/// Gözlükten (gerçek BLE) ya da test modundan (simülasyon) gelen, henüz
/// işlenmemiş ham komut. Python tarafındaki `siniflandir()` çıktısının
/// (intent, entity, cevap) karşılığı.
class BleCommand {
  final PatikaIntent intent;
  final String? entity;

  /// MESAJ: komutta "WhatsApp" geçtiyse [MessageApp.whatsapp]; null ise
  /// Ayarlar'daki varsayılan uygulama. Gözlükten gelen komutta hep null.
  final MessageApp? messageApp;

  const BleCommand({required this.intent, this.entity, this.messageApp});

  factory BleCommand.fromWire(String intentRaw, String? entity) {
    return BleCommand(
      intent: PatikaIntent.fromWireName(intentRaw),
      entity: (entity == null || entity.trim().isEmpty) ? null : entity.trim(),
    );
  }

  @override
  String toString() => 'BleCommand(intent: $intent, entity: $entity'
      '${messageApp == null ? '' : ', app: ${messageApp!.name}'})';
}
