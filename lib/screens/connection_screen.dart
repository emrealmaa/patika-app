import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ble/ble_connection_state.dart';
import '../ble/patika_ble_service.dart';
import '../commands/log_entry.dart';
import '../theme/app_theme.dart';

/// Bağlantı durumu ekranı: gerçek/simülasyon mod seçimi, tarama, cihaza
/// bağlanma ve son işlenen komutların (her iki mod için de) kısa geçmişi.
///
/// Erişilebilirlik-öncelikli tasarım kurallarına göre yazıldı (bkz.
/// patika_app/TODO.md "Erişilebilirlik" geçmişi): tek sütun/doğrusal
/// düzen, büyük dokunma alanları (global tema - bkz. app_theme.dart),
/// hiçbir durum sadece renkle anlatılmıyor, dekoratif ikonlar
/// ExcludeSemantics ile TalkBack'ten gizleniyor.
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
        // Tek sütun/doğrusal düzen: butonlar yan yana (Row) değil alt alta.
        ElevatedButton.icon(
          onPressed: () => state.startScan(),
          icon: const Icon(Icons.search),
          label: const Text('Tara'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: state.connectionState == BleConnectionState.connected
              ? () => state.disconnect()
              : null,
          icon: const Icon(Icons.link_off),
          label: const Text('Bağlantıyı kes'),
        ),
        const SizedBox(height: 16),
        Text('Bulunan cihazlar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.devices.isEmpty)
          const Text('Henüz cihaz bulunamadı.')
        else
          ...state.devices.map((d) => _DeviceCard(device: d, onConnect: () => state.connect(d.id))),
        const SizedBox(height: 24),
        Text('Son komutlar', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.log.isEmpty)
          const Text('Henüz işlenen bir komut yok.')
        else
          ...state.log.take(10).map((e) => _LogTile(entry: e)),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onConnect;

  const _DeviceCard({required this.device, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ExcludeSemantics(child: Icon(Icons.bluetooth)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(device.id),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: '${device.name} cihazına bağlan',
              excludeSemantics: true,
              child: ElevatedButton(
                onPressed: onConnect,
                child: const Text('Bağlan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Log satırının görsel düzeni (ikon + başlık + alt yazı, `ListTile` içinde)
/// bilinçli olarak korundu - TalkBack zaten lineer okuyor, yan yana rakip
/// kontrol değil sıralı bilgi. Buradaki tek değişiklik: ikon+renk artık TEK
/// BAŞINA "başarılı/başarısız" anlamı taşımıyor - tüm satır tek, açık bir
/// Semantics etiketine sarılı, ikon dekoratif kabul edilip gizlendi.
class _LogTile extends StatelessWidget {
  final LogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final durum = entry.result.success ? 'başarılı' : 'başarısız';
    final baslik = '${entry.intent.name}${entry.entity != null ? " (${entry.entity})" : ""}';

    return Semantics(
      label: '$baslik, $durum: ${entry.result.message}',
      excludeSemantics: true,
      child: ListTile(
        dense: true,
        leading: ExcludeSemantics(
          child: Icon(
            entry.result.success ? Icons.check_circle : Icons.error_outline,
            color: entry.result.success ? AppColors.success : AppColors.warning,
          ),
        ),
        title: Text(baslik),
        subtitle: Text('${entry.result.success ? "Başarılı" : "Başarısız"}: ${entry.result.message}'),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BleConnectionState connectionState;

  const _StatusCard({required this.connectionState});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (connectionState) {
      BleConnectionState.disconnected => ('Bağlı değil', AppColors.neutral),
      BleConnectionState.scanning => ('Taranıyor…', AppColors.info),
      BleConnectionState.connecting => ('Bağlanıyor…', AppColors.warning),
      BleConnectionState.connected => ('Bağlı', AppColors.success),
    };

    return Semantics(
      label: 'Bağlantı durumu: $label',
      excludeSemantics: true,
      child: Card(
        child: ListTile(
          leading: ExcludeSemantics(child: Icon(Icons.circle, color: color, size: 16)),
          // Durum HER ZAMAN beyaz, yüksek kontrastlı metinle yazılıyor -
          // renk (yukarıdaki nokta) sadece yardımcı/dekoratif işaret,
          // hiçbir zaman tek başına anlam taşımıyor (bkz. AppColors).
          title: Text(
            label,
            style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
