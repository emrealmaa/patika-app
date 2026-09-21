import '../commands/intent.dart';

/// Gözlükten (gerçek BLE) ya da test modundan (simülasyon) gelen, henüz
/// işlenmemiş ham komut. Python tarafındaki `siniflandir()` çıktısının
/// (intent, entity, cevap) karşılığı.
class BleCommand {
  final PatikaIntent intent;
  final String? entity;

  const BleCommand({required this.intent, this.entity});

  factory BleCommand.fromWire(String intentRaw, String? entity) {
    return BleCommand(
      intent: PatikaIntent.fromWireName(intentRaw),
      entity: (entity == null || entity.trim().isEmpty) ? null : entity.trim(),
    );
  }

  @override
  String toString() => 'BleCommand(intent: $intent, entity: $entity)';
}
