import 'package:flutter/material.dart';

import '../app_state.dart';

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
          const Card(
            color: Color(0xFFFFF3CD),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Test modu sadece simülasyon modundayken çalışır. '
                'Bağlantı ekranından "Simülasyon modu"nu açın.',
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
          ...state.log.map(
            (e) => Card(
              child: ListTile(
                leading: Icon(
                  e.result.success ? Icons.check_circle : Icons.error_outline,
                  color: e.result.success ? Colors.green : Colors.orange,
                ),
                title: Text('${e.intent.name}${e.entity != null ? " (${e.entity})" : ""}'),
                subtitle: Text(e.result.message),
                trailing: Text(
                  '${e.time.hour.toString().padLeft(2, '0')}:'
                  '${e.time.minute.toString().padLeft(2, '0')}:'
                  '${e.time.second.toString().padLeft(2, '0')}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
