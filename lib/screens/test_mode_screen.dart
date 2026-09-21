import 'package:flutter/material.dart';

import '../app_state.dart';
import '../commands/log_entry.dart';
import '../theme/app_theme.dart';

/// Gözlük donanımı olmadan komut akışını (parse -> route -> handler -> log)
/// uçtan uca test etmek için sahte komut enjekte eden ekran. Sadece
/// simülasyon modundayken anlamlı - gerçek moddayken bir uyarı gösterir.
class TestModeScreen extends StatefulWidget {
  final AppState state;

  const TestModeScreen({super.key, required this.state});

  @override
  State<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends State<TestModeScreen> {
  final _entityController = TextEditingController();
  String _selectedIntent = 'ARA';

  static const _intents = [
    'ARA',
    'MESAJ',
    'HAVA',
    'SAAT',
    'MÜZİK',
    'HABER',
    'OKU',
    'GECIS_MODU',
    'NAVİGASYON',
    'BİLİNMİYOR',
  ];

  @override
  void dispose() {
    _entityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!state.isSimulated)
          Card(
            // Uyarı zaten metinle anlatılıyor (Kural 5) - burada sadece
            // koyu zemin + beyaz metinle AAA kontrastı garanti ediliyor
            // (açık sarı zemin + varsayılan koyu metin karanlık temada
            // düşük kontrast üretirdi).
            color: const Color(0xFF4A3600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: AppColors.warning),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  ExcludeSemantics(child: Icon(Icons.warning_amber, color: AppColors.warning)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Test modu sadece simülasyon modundayken çalışır. '
                      'Bağlantı ekranından "Simülasyon modu"nu açın.',
                      style: TextStyle(color: AppColors.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedIntent,
          decoration: const InputDecoration(labelText: 'Niyet (intent)'),
          items: _intents
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: (v) => setState(() => _selectedIntent = v ?? _selectedIntent),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _entityController,
          decoration: const InputDecoration(
            labelText: 'Entity (isim/yer, opsiyonel)',
            hintText: 'örn. Emre, Kadıköy iskelesi',
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: state.isSimulated
              ? () {
                  final entity = _entityController.text.trim();
                  state.injectTestCommand(
                    _selectedIntent,
                    entity: entity.isEmpty ? null : entity,
                  );
                }
              : null,
          icon: const Icon(Icons.send),
          label: const Text('Komutu gönder'),
        ),
        const SizedBox(height: 24),
        Text('İşlem geçmişi', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.log.isEmpty)
          const Text('Henüz işlenen bir komut yok.')
        else
          ...state.log.map((e) => _LogCard(entry: e)),
      ],
    );
  }
}

/// Görsel düzen (ikon + başlık + alt yazı + saat, `ListTile` içinde)
/// bilinçli olarak korundu - TalkBack zaten lineer okuyor, yan yana rakip
/// kontrol değil sıralı bilgi. Buradaki tek değişiklik: ikon+renk artık TEK
/// BAŞINA "başarılı/başarısız" anlamı taşımıyor, saat de artık anlamlı bir
/// etikete sahip - tüm satır tek, açık bir Semantics etiketine sarılı.
class _LogCard extends StatelessWidget {
  final LogEntry entry;

  const _LogCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final durum = entry.result.success ? 'başarılı' : 'başarısız';
    final baslik = '${entry.intent.name}${entry.entity != null ? " (${entry.entity})" : ""}';
    final saat = '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}';

    return Semantics(
      label: '$baslik, $durum: ${entry.result.message}. İşlem saati $saat',
      excludeSemantics: true,
      child: Card(
        child: ListTile(
          leading: ExcludeSemantics(
            child: Icon(
              entry.result.success ? Icons.check_circle : Icons.error_outline,
              color: entry.result.success ? AppColors.success : AppColors.warning,
            ),
          ),
          title: Text(baslik),
          subtitle: Text('${entry.result.success ? "Başarılı" : "Başarısız"}: ${entry.result.message}'),
          trailing: Text(saat),
        ),
      ),
    );
  }
}
