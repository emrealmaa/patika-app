import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ble/ble_connection_state.dart';
import '../ble/patika_ble_service.dart';
import '../commands/log_entry.dart';
import '../l10n/strings_tr.dart';
import '../theme/app_theme.dart';
import '../widgets/kisa_ozet_kart.dart';
import '../widgets/liste_satiri.dart';
import '../widgets/patika_card.dart';

/// Bağlantı durumu ekranı: tarama, cihaza bağlanma ve son işlenen
/// komutların kısa geçmişi.
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
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PatikaTokens.screenPadding,
        PatikaTokens.gapSmall,
        PatikaTokens.screenPadding,
        PatikaTokens.gap,
      ),
      children: [
        _StatusCard(
          connectionState: state.connectionState,
          battery: state.glassesBattery,
        ),
        const SizedBox(height: PatikaTokens.gap),
        // Tek sütun/doğrusal düzen: butonlar yan yana (Row) değil alt alta.
        ElevatedButton.icon(
          onPressed: () => state.startScan(),
          icon: const Icon(Icons.search),
          label: const Text(Tr.scan),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: state.connectionState == BleConnectionState.connected
              ? () => state.disconnect()
              : null,
          icon: const Icon(Icons.link_off),
          label: const Text(Tr.disconnect),
        ),
        const SizedBox(height: 24),
        _SectionHeader(Tr.foundDevices),
        if (state.devices.isEmpty)
          Text(Tr.noDevices, style: text.bodyMedium)
        else
          for (final d in state.devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DeviceCard(device: d, onConnect: () => state.connect(d.id)),
            ),
        const SizedBox(height: 24),
        _SectionHeader(Tr.recentCommands),
        if (state.log.isEmpty)
          Text(Tr.noCommands, style: text.bodyMedium)
        else
          PatikaCard(
            padding: const EdgeInsets.symmetric(horizontal: PatikaTokens.gap, vertical: 4),
            child: Column(
              children: [
                for (final (i, e) in state.log.take(10).indexed)
                  _LogTile(entry: e, divider: i < state.log.take(10).length - 1),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const KisaOzetKart(
          title: Tr.howToConnectTitle,
          summary: Tr.howToConnectSummary,
          details: Tr.howToConnectSteps,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PatikaTokens.gapSmall),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onConnect;

  const _DeviceCard({required this.device, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return PatikaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PatikaTokens.primarySoft,
                    borderRadius: BorderRadius.circular(PatikaTokens.radiusIconBox),
                  ),
                  child: const Icon(Icons.bluetooth, color: PatikaTokens.primary),
                ),
              ),
              const SizedBox(width: 12),
              // Ham cihaz kimliği (MAC/UUID) kullanıcıya gösterilmez.
              Expanded(
                child: Text(device.name, style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Etiket butonun İÇİNDE: dışarıdan excludeSemantics ile sarmak
          // butonun dokunma eylemini de siler, TalkBack'te çift dokunuş
          // hiçbir şey yapmaz.
          FilledButton(
            onPressed: onConnect,
            child: Semantics(
              label: Tr.connectTo(device.name),
              excludeSemantics: true,
              child: const Text(Tr.connect),
            ),
          ),
        ],
      ),
    );
  }
}

/// Log satırı: ikon + başlık + alt yazı. İkon ve renk TEK BAŞINA
/// "başarılı/başarısız" anlamı taşımıyor - alt yazıda "Başarılı/Başarısız"
/// yazıyor ve tüm satır tek, açık bir Semantics etiketiyle okunuyor; ikon
/// süs.
class _LogTile extends StatelessWidget {
  final LogEntry entry;
  final bool divider;

  const _LogTile({required this.entry, required this.divider});

  @override
  Widget build(BuildContext context) {
    final ok = entry.result.success;
    final baslik = '${Tr.commandName(entry.intent.name)}${entry.entity != null ? " (${entry.entity})" : ""}';

    return ListeSatiri(
      icon: ok ? Icons.check_circle_outline : Icons.error_outline,
      danger: !ok,
      title: baslik,
      subtitle: '${ok ? Tr.success : Tr.failure}: ${entry.result.message}',
      semanticLabel: Tr.logEntryLabel(baslik, ok, entry.result.message),
      divider: divider,
    );
  }
}

/// Gradyanlı durum kartı. TalkBack tek cümle okur ("Bağlantı durumu: Bağlı,
/// gözlük pili yüzde 80"); ikon ve halkalar süs. Durum her zaman yazıyla
/// verilir, ikon yalnızca yardımcı işaret.
class _StatusCard extends StatelessWidget {
  final BleConnectionState connectionState;
  final int? battery;

  const _StatusCard({required this.connectionState, this.battery});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (connectionState) {
      BleConnectionState.disconnected => (Tr.stateDisconnected, Icons.bluetooth_disabled),
      BleConnectionState.scanning => (Tr.stateScanning, Icons.bluetooth_searching),
      BleConnectionState.connecting => (Tr.stateConnecting, Icons.bluetooth_searching),
      BleConnectionState.connected => (Tr.stateConnected, Icons.bluetooth_connected),
    };
    final searching = connectionState == BleConnectionState.scanning ||
        connectionState == BleConnectionState.connecting;

    final battery = this.battery;
    // Ekranda "%80", TalkBack'te "yüzde 80" (okunuşu net olsun).
    final spoken = battery == null
        ? Tr.connectionStatus(label)
        : '${Tr.connectionStatus(label)}, ${Tr.batterySpoken(battery)}';

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: PatikaCard.hero(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: PatikaTokens.onHero),
          child: Row(
            children: [
              _SignalIcon(icon: icon, searching: searching),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      Tr.connectionHeroCaption,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    if (battery != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        Tr.batteryVisual(battery),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Durum kartındaki beyaz daire ve (tarama/bağlanma sürerken) çevresindeki
/// dalga halkaları. Tamamı süs.
class _SignalIcon extends StatelessWidget {
  static const size = 84.0;

  final IconData icon;
  final bool searching;

  const _SignalIcon({required this.icon, required this.searching});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (searching)
              Container(
                key: const ValueKey('baglanti-dalgalari'),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PatikaTokens.onHero.withValues(alpha: 0.25),
                ),
              ),
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: PatikaTokens.onHero,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: PatikaTokens.primary),
            ),
          ],
        ),
      ),
    );
  }
}
