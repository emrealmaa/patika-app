import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ble/ble_connection_state.dart';
import '../ble/patika_ble_service.dart';
import '../commands/log_entry.dart';
import '../l10n/strings_tr.dart';
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
        _StatusCard(
          connectionState: state.connectionState,
          battery: state.glassesBattery,
        ),
        const SizedBox(height: 16),
        // Tek sütun/doğrusal düzen: butonlar yan yana (Row) değil alt alta.
        ElevatedButton.icon(
          onPressed: () => state.startScan(),
          icon: const Icon(Icons.search),
          label: const Text(Tr.scan),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: state.connectionState == BleConnectionState.connected
              ? () => state.disconnect()
              : null,
          icon: const Icon(Icons.link_off),
          label: const Text(Tr.disconnect),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(Tr.foundDevices, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        if (state.devices.isEmpty)
          const Text(Tr.noDevices)
        else
          ...state.devices.map((d) => _DeviceCard(device: d, onConnect: () => state.connect(d.id))),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(Tr.recentCommands, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        if (state.log.isEmpty)
          const Text(Tr.noCommands)
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
                    // Ham cihaz kimliği (MAC/UUID) kullanıcıya gösterilmez.
                    children: [
                      Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Etiket butonun İÇİNDE: dışarıdan excludeSemantics ile sarmak
            // butonun dokunma eylemini de siler, TalkBack'te çift dokunuş
            // hiçbir şey yapmaz.
            ElevatedButton(
              onPressed: onConnect,
              child: Semantics(
                label: Tr.connectTo(device.name),
                excludeSemantics: true,
                child: const Text(Tr.connect),
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
    final ok = entry.result.success;
    final baslik = '${Tr.commandName(entry.intent.name)}${entry.entity != null ? " (${entry.entity})" : ""}';

    return Semantics(
      label: Tr.logEntryLabel(baslik, ok, entry.result.message),
      excludeSemantics: true,
      child: ListTile(
        dense: true,
        leading: ExcludeSemantics(
          child: Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? AppColors.success : AppColors.warning,
          ),
        ),
        title: Text(baslik),
        subtitle: Text('${ok ? Tr.success : Tr.failure}: ${entry.result.message}'),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BleConnectionState connectionState;
  final int? battery;

  const _StatusCard({required this.connectionState, this.battery});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (connectionState) {
      BleConnectionState.disconnected => (Tr.stateDisconnected, AppColors.neutral),
      BleConnectionState.scanning => (Tr.stateScanning, AppColors.info),
      BleConnectionState.connecting => (Tr.stateConnecting, AppColors.warning),
      BleConnectionState.connected => (Tr.stateConnected, AppColors.success),
    };

    final battery = this.battery;
    // Ekranda "%80", TalkBack'te "yüzde 80" (okunuşu net olsun).
    final spoken = battery == null
        ? Tr.connectionStatus(label)
        : '${Tr.connectionStatus(label)}, ${Tr.batterySpoken(battery)}';

    return Semantics(
      label: spoken,
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
          subtitle: battery == null ? null : Text(Tr.batteryVisual(battery)),
        ),
      ),
    );
  }
}
