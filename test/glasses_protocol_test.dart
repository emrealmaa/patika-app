import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/haptic_patterns.dart';
import 'package:patika_app/ble/glasses_protocol.dart';
import 'package:patika_app/commands/intent.dart';

void main() {
  GlassesMessage? decode(String json) => GlassesProtocol.decode(utf8.encode(json));

  group('gözlük -> telefon', () {
    test('komut', () {
      final m = decode('{"t":"cmd","intent":"ARA","entity":"Emre"}') as CommandMessage;
      expect(m.command.intent, PatikaIntent.ara);
      expect(m.command.entity, 'Emre');
    });

    test('eski "t"siz komut formatı hâlâ çalışır', () {
      final m = decode('{"intent":"SAAT"}') as CommandMessage;
      expect(m.command.intent, PatikaIntent.saat);
    });

    test('Türkçe karakterli komut (UTF-8)', () {
      final m = decode('{"t":"cmd","intent":"NAVİGASYON","entity":"Kadıköy İskelesi"}')
          as CommandMessage;
      expect(m.command.intent, PatikaIntent.navigasyon);
      expect(m.command.entity, 'Kadıköy İskelesi');
    });

    test('buton olayları', () {
      expect((decode('{"t":"btn","a":"tap"}') as ButtonMessage).button, GlassesButton.tap);
      expect((decode('{"t":"btn","a":"double"}') as ButtonMessage).button,
          GlassesButton.doubleTap);
      expect((decode('{"t":"btn","a":"long"}') as ButtonMessage).button,
          GlassesButton.longPress);
    });

    test('jest', () {
      expect((decode('{"t":"gst","g":"nod2"}') as GestureMessage).gesture,
          GlassesGesture.doubleNod);
    });

    test('pil 0-100 aralığına kırpılır', () {
      expect((decode('{"t":"batt","v":87}') as BatteryMessage).percent, 87);
      expect((decode('{"t":"batt","v":140}') as BatteryMessage).percent, 100);
    });

    test('heartbeat (seq opsiyonel)', () {
      expect((decode('{"t":"hb","seq":42}') as HeartbeatMessage).seq, 42);
      expect((decode('{"t":"hb"}') as HeartbeatMessage).seq, isNull);
    });

    test('bozuk/tanınmayan mesajlar null döner, çökmez', () {
      expect(GlassesProtocol.decode([]), isNull);
      expect(GlassesProtocol.decode([0xff, 0xfe]), isNull);
      expect(decode('bozuk json'), isNull);
      expect(decode('[1,2]'), isNull);
      expect(decode('{"t":"gelecekte_eklenecek"}'), isNull);
      expect(decode('{"t":"btn","a":"üçlü"}'), isNull);
      expect(decode('{"t":"batt","v":"yüksek"}'), isNull);
      expect(decode('{}'), isNull);
    });
  });

  group('telefon -> gözlük', () {
    test('titreşim deseni ID ve yüzde şiddetle kodlanır', () {
      final bytes = GlassesProtocol.encodeHaptic(HapticPatternId.turnLeft, 0.7);
      expect(jsonDecode(utf8.decode(bytes)), {'t': 'hap', 'id': 9, 's': 70});
    });

    test('en uzun mesaj 244 baytlık BLE yüküne sığar', () {
      final bytes = GlassesProtocol.encodeHaptic(HapticPatternId.turnRight, 1);
      expect(bytes.length, lessThan(244));
    });
  });
}
