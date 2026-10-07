import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/platform/call_service.dart';
import 'package:patika_app/platform/simulated_call_service.dart';

void main() {
  group('SimulatedCallService', () {
    test('startCall yayınlar, answer/reject null yayınlayıp bitirir', () async {
      final sim = SimulatedCallService();
      final events = <IncomingCall?>[];
      final sub = sim.incomingCall.listen(events.add);

      sim.startCall('Ahmet Yılmaz', number: '05550000001');
      await Future(() {});
      expect(events.single?.callerName, 'Ahmet Yılmaz');
      expect(events.single?.number, '05550000001');
      expect(sim.current?.callerName, 'Ahmet Yılmaz');

      await sim.answer();
      await Future(() {});
      expect(events.last, isNull);
      expect(sim.current, isNull);

      await sub.cancel();
      sim.dispose();
    });

    test('çalmıyorken answer/reject sessizce hiçbir şey yapmaz', () async {
      final sim = SimulatedCallService();
      final events = <IncomingCall?>[];
      final sub = sim.incomingCall.listen(events.add);

      await sim.reject();
      await Future(() {});
      expect(events, isEmpty, reason: 'zaten null olan durum yeniden yayınlanmamalı');

      await sub.cancel();
      sim.dispose();
    });

    test('yeni startCall eskisinin yerine geçer', () async {
      final sim = SimulatedCallService();
      sim.startCall('Ahmet Yılmaz');
      sim.startCall('Ayşe Demir');
      expect(sim.current?.callerName, 'Ayşe Demir');
      sim.dispose();
    });
  });
}
