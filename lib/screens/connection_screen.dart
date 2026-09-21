import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ble/ble_connection_state.dart';

/// Bağlantı durumu ekranı: gerçek/simülasyon mod seçimi, tarama, cihaza
/// bağlanma ve son işlenen komutların (her iki mod için de) kısa geçmişi.
class ConnectionScreen extends StatelessWidget {
  final AppState state;

  const ConnectionScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Simülasyon modu'),
          subtitle: Text(state.isSimulated
              ? 'Gözlük donanımı simüle ediliyor'
              : 'Gerçek BLE ile taranıyor (donanım gerekir)'),
          value: state.isSimulated,
          onChanged: (v) => state.toggleMode(v),
        ),
        const SizedBox(height: 16),
        _StatusCard(connectionState: state.connectionState),
        const SizedBox(height: 16),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => state.startScan(),
              icon: const Icon(Icons.search),
              label: const Text('Tara'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: state.connectionState == BleConnectionState.connected
                  ? () => state.disconnect()
                  : null,
              icon: const Icon(Icons.link_off),
              label: const Text('Bağlantıyı kes'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Bulunan cihazlar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.devices.isEmpty)
          const Text('Henüz cihaz bulunamadı.')
        else
          ...state.devices.map(
            (d) => Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name),
                subtitle: Text(d.id),
                trailing: ElevatedButton(
                  onPressed: () => state.connect(d.id),
                  child: const Text('Bağlan'),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Son komutlar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.log.isEmpty)
          const Text('Henüz işlenen bir komut yok.')
        else
          ...state.log.take(10).map(
                (e) => ListTile(
                  dense: true,
                  leading: Icon(
                    e.result.success ? Icons.check_circle : Icons.error_outline,
                    color: e.result.success ? Colors.green : Colors.orange,
                  ),
                  title: Text('${e.intent.name}${e.entity != null ? " (${e.entity})" : ""}'),
                  subtitle: Text(e.result.message),
                ),
              ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BleConnectionState connectionState;

  const _StatusCard({required this.connectionState});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (connectionState) {
      BleConnectionState.disconnected => ('Bağlı değil', Colors.grey),
      BleConnectionState.scanning => ('Taranıyor…', Colors.blue),
      BleConnectionState.connecting => ('Bağlanıyor…', Colors.orange),
      BleConnectionState.connected => ('Bağlı', Colors.green),
    };

    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(Icons.circle, color: color, size: 16),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
