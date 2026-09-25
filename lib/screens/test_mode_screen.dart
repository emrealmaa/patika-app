import 'package:flutter/material.dart';

import '../accessibility/a11y_announcer.dart' as a11y;
import '../app_state.dart';
import '../commands/log_entry.dart';
import '../commands/voice_intent_classifier.dart';
import '../theme/app_theme.dart';
import '../voice/speech_input_service.dart';

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
        _VoiceCommandButton(state: state),
        const SizedBox(height: 24),
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
                      'Elle komut gönderme sadece simülasyon modundayken '
                      'çalışır. Bağlantı ekranından "Simülasyon modu"nu '
                      'açın. Sesli komut her iki modda da çalışır.',
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

enum _VoicePhase { idle, preparing, listening, processing }

/// Telefonun kendi mikrofonuyla komut verme butonu - girdi kaynağı klavye
/// yerine ses; tanınan metin [classifyVoiceCommand] ile BleCommand'e
/// çevrilip diğer kaynaklarla aynı yoldan (AppState -> CommandRouter)
/// işleniyor.
///
/// Basılı tutma yerine dokunarak aç/kapat: TalkBack/VoiceOver açıkken
/// basılı tutmak "çift dokun ve tut" gerektirir, görme engelli kullanıcı
/// için zahmetli. Motor, kullanıcı susunca dinlemeyi kendisi bitirir.
class _VoiceCommandButton extends StatefulWidget {
  final AppState state;

  const _VoiceCommandButton({required this.state});

  @override
  State<_VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<_VoiceCommandButton> {
  /// Duyuru ile sonraki adım arasındaki bekleme. `announce` bitişini
  /// bildirmiyor; bu olmadan ekran okuyucunun "Dinliyorum" sesi mikrofona
  /// komut olarak girebilir ya da "Şunu anladım" duyurusu komut sonucunun
  /// duyurusuyla kesilebilir.
  static const _announceGap = Duration(milliseconds: 1200);

  final _speech = SpeechInputService();
  _VoicePhase _phase = _VoicePhase.idle;
  String? _lastHeard;

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  void _setPhase(_VoicePhase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  Future<void> _onTap() async {
    switch (_phase) {
      case _VoicePhase.processing:
        return;
      case _VoicePhase.preparing:
      case _VoicePhase.listening:
        await _speech.cancel();
        _setPhase(_VoicePhase.idle);
        a11y.announce('Dinleme iptal edildi');
        return;
      case _VoicePhase.idle:
        break;
    }

    _setPhase(_VoicePhase.preparing);
    final ready = await _speech.init();
    if (_phase != _VoicePhase.preparing) return;
    if (!ready) {
      _setPhase(_VoicePhase.idle);
      a11y.announce(
          'Mikrofon izni verilmedi ya da konuşma tanıma bu cihazda kullanılamıyor');
      return;
    }

    a11y.announce('Dinliyorum');
    await Future.delayed(_announceGap);
    // Beklerken iptal edildiyse ya da ekrandan çıkıldıysa dinlemeye başlama.
    if (!mounted || _phase != _VoicePhase.preparing) return;

    _setPhase(_VoicePhase.listening);
    await _speech.listen(
      onFinal: _onFinal,
      onError: _onError,
      onDone: () => _onError('Sizi duyamadım, tekrar deneyin'),
    );
  }

  Future<void> _onFinal(String text) async {
    if (_phase != _VoicePhase.listening) return;
    if (text.isEmpty) {
      _onError('Sizi duyamadım, tekrar deneyin');
      return;
    }

    setState(() {
      _phase = _VoicePhase.processing;
      _lastHeard = text;
    });
    a11y.announce('Şunu anladım: $text');
    await Future.delayed(_announceGap);

    // Komut anlaşıldı - kullanıcı bu arada sekmeden çıksa bile işleniyor.
    // Sonuç duyurusunu AppState yapıyor (diğer kaynaklarla aynı).
    await widget.state.submitVoiceCommand(classifyVoiceCommand(text));
    _setPhase(_VoicePhase.idle);
  }

  void _onError(String message) {
    if (_phase != _VoicePhase.listening) return;
    _setPhase(_VoicePhase.idle);
    a11y.announce(message);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, text, semanticLabel) = switch (_phase) {
      _VoicePhase.idle => (
          Icons.mic,
          'Sesli Komut Ver',
          'Sesli komut ver. Dokunun ve komutunuzu söyleyin.',
        ),
      _VoicePhase.preparing || _VoicePhase.listening => (
          Icons.stop_circle_outlined,
          'Dinleniyor… Durdurmak için dokunun',
          'Dinleniyor. Durdurmak için dokunun.',
        ),
      _VoicePhase.processing => (
          Icons.hourglass_top,
          'Komut işleniyor…',
          'Komut işleniyor, lütfen bekleyin.',
        ),
    };
    // Durum renkle değil metin+ikonla anlatılıyor; renk yardımcı işaret.
    final active = _phase != _VoicePhase.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _onTap,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 120),
            backgroundColor: active ? AppColors.warning : AppColors.info,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          // Buton kendi alt ağacının etiketini birleştiriyor; ikon ve kısa
          // görsel metin yerine tek, açıklayıcı bir etiket okunsun.
          child: Semantics(
            label: semanticLabel,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48),
                  const SizedBox(height: 8),
                  Text(text, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        if (_lastHeard != null) ...[
          const SizedBox(height: 8),
          Text('Son duyulan: "$_lastHeard"'),
        ],
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
