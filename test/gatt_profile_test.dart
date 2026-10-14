import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/glasses_gatt_profile.dart';

/// Madde 6: BLE UUID'lerinin tek kaynağı [GlassesGattProfile]. Varsayılan hâlâ
/// placeholder (firmware yok); dart-define ile geçersiz kılınabilir.
void main() {
  final uuid = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

  test('lib/ içinde UUID sabiti yalnızca glasses_gatt_profile.dart\'ta', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('lib/ble/glasses_gatt_profile.dart')) continue;
      if (uuid.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });

  test('derleme varsayılanı placeholder ve açıkça öyle işaretli', () {
    final p = GlassesGattProfile.fromDefines();
    expect(p.isPlaceholder, isTrue);
    expect(p.invalid, isEmpty);
    expect(p.service, '0000ff10-0000-1000-8000-00805f9b34fb');
  });

  test('geçerli değer kullanılır (küçük harfe), geçersiz olan placeholder + raporlanır', () {
    final p = GlassesGattProfile.resolve(
      service: '12345678-ABCD-1234-ABCD-1234567890AB',
      event: 'bozuk',
    );
    expect(p.service, '12345678-abcd-1234-abcd-1234567890ab');
    expect(p.eventCharacteristic, GlassesGattProfile.placeholder.eventCharacteristic);
    expect(p.controlCharacteristic, GlassesGattProfile.placeholder.controlCharacteristic);
    expect(p.invalid, ['PATIKA_BLE_EVENT_UUID']);
    expect(p.isPlaceholder, isFalse);
  });

  test('belge aynı placeholder değerleri ve dart-define adlarını anlatıyor', () {
    final doc = File('docs/ble_protocol.md').readAsStringSync();
    for (final v in [
      GlassesGattProfile.placeholder.service,
      GlassesGattProfile.placeholder.eventCharacteristic,
      GlassesGattProfile.placeholder.controlCharacteristic,
      'PATIKA_BLE_SERVICE_UUID',
      'PATIKA_BLE_EVENT_UUID',
      'PATIKA_BLE_CONTROL_UUID',
    ]) {
      expect(doc, contains(v));
    }
  });
}
