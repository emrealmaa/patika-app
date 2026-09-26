import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/ble/ble_connection_state.dart';
import 'package:patika_app/ble/connection_supervisor.dart';
import 'package:patika_app/ble/device_memory.dart';
import 'package:patika_app/ble/simulated_ble_service.dart';

/// Denetçi gerçek SimulatedBleService'e karşı, zaman fake_async ile
/// ilerletilerek test ediliyor - simülasyonun kendi gecikmeleri (tarama
/// 600 ms, bağlanma 500 ms, heartbeat 2 sn) de dahil.
void main() {
  late SimulatedBleService sim;
  late MemoryDeviceMemory memory;
  late ConnectionSupervisor supervisor;
  late List<String> events;
  late List<BleConnectionState> states;

  void setUpSupervisor({String? lastDevice}) {
    sim = SimulatedBleService();
    memory = MemoryDeviceMemory(lastDevice);
    events = [];
    states = [];
    sim.connectionState.listen(states.add);
    supervisor = ConnectionSupervisor(
      sim,
      memory,
      onHealthy: () => events.add('healthy'),
      onLost: () => events.add('lost'),
      onPersistentFailure: () => events.add('notice'),
      jitter: () => 0,
    );
  }

  void tearDownSupervisor() {
    supervisor.dispose();
    sim.dispose();
  }

  test('geri çekilme: 1, 2, 4, 8, 16, 30, 30 sn; jitter uygulanır', () {
    final delays = [for (var i = 1; i <= 7; i++) ConnectionSupervisor.backoffDelay(i).inSeconds];
    expect(delays, [1, 2, 4, 8, 16, 30, 30]);
    expect(ConnectionSupervisor.backoffDelay(3, jitter: 0.2).inMilliseconds, 4800);
  });

  test('açılışta son cihaz biliniyorsa taramadan ona bağlanır', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 1));
      expect(states, isNot(contains(BleConnectionState.scanning)));
      expect(states.last, BleConnectionState.connected);
      expect(events, ['healthy']);
      tearDownSupervisor();
    });
  });

  test('açılışta cihaz bilinmiyorsa tarar, tek gözlük bulunca bağlanır ve hatırlar', () {
    fakeAsync((async) {
      setUpSupervisor();
      supervisor.start();
      async.elapse(const Duration(seconds: 2));
      expect(states.first, BleConnectionState.scanning);
      expect(states.last, BleConnectionState.connected);
      expect(memory.value, 'SIM-ESP32-S3-0001');
      tearDownSupervisor();
    });
  });

  test('kopunca 1 sn sonra yeniden bağlanır, tek "koptu" + "bağlandı"', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 1));

      sim.setReachable(false);
      sim.setReachable(true);
      async.elapse(const Duration(milliseconds: 900));
      expect(states.last, BleConnectionState.disconnected, reason: 'henüz 1 sn dolmadı');
      async.elapse(const Duration(seconds: 1));
      expect(states.last, BleConnectionState.connected);
      expect(events, ['healthy', 'lost', 'healthy']);
      tearDownSupervisor();
    });
  });

  test('menzil dışında: 3 başarısız denemeden sonra BİR KEZ haber verir, dönünce bağlanır', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 1));

      sim.setReachable(false);
      // Kopma +1 sn deneme(0,5 sn) +2 sn deneme +4 sn deneme = ~8,5 sn
      async.elapse(const Duration(seconds: 7));
      expect(events, ['healthy', 'lost'], reason: 'henüz 3. deneme bitmedi');
      async.elapse(const Duration(seconds: 2));
      expect(events, ['healthy', 'lost', 'notice']);
      expect(supervisor.failedAttempts, 3);

      // Uyarı tekrar edilmez; denemeler 30 sn'ye kadar seyrelerek sürer.
      async.elapse(const Duration(minutes: 2));
      expect(events.where((e) => e == 'notice'), hasLength(1));

      sim.setReachable(true);
      async.elapse(const Duration(seconds: 31));
      expect(states.last, BleConnectionState.connected);
      expect(events.last, 'healthy');
      expect(supervisor.failedAttempts, 0);
      tearDownSupervisor();
    });
  });

  test('heartbeat kesilirse 6 sn içinde kopmuş sayılır ve yeniden bağlanır', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 3)); // bağlandı + ilk heartbeat
      expect(events, ['healthy']);

      sim.setHeartbeatPaused(true);
      async.elapse(const Duration(seconds: 7));
      expect(events, ['healthy', 'lost']);

      sim.setHeartbeatPaused(false);
      async.elapse(const Duration(seconds: 5));
      expect(states.last, BleConnectionState.connected);
      expect(events, ['healthy', 'lost', 'healthy']);
      tearDownSupervisor();
    });
  });

  test('donmuş gözlük "bağlandı/koptu" döngüsüne girmez, sonunda haber verir', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 3));

      // BLE bağlantısı kuruluyor ama heartbeat hiç gelmiyor.
      sim.setHeartbeatPaused(true);
      async.elapse(const Duration(minutes: 1));
      expect(events, ['healthy', 'lost', 'notice'],
          reason: 'her yeniden bağlanmada "bağlandı" denmemeli');
      expect(supervisor.isHealthy, isFalse);
      tearDownSupervisor();
    });
  });

  test('kullanıcı bağlantıyı keserse yeniden bağlanmaz ve "koptu" demez', () {
    fakeAsync((async) {
      setUpSupervisor(lastDevice: 'SIM-ESP32-S3-0001');
      supervisor.start();
      async.elapse(const Duration(seconds: 1));

      supervisor.disconnect();
      async.elapse(const Duration(minutes: 1));
      expect(states.last, BleConnectionState.disconnected);
      expect(events, ['healthy']);
      expect(supervisor.isReconnecting, isFalse);
      tearDownSupervisor();
    });
  });
}
