import 'package:flutter/material.dart';

import '../accessibility/feedback_hub.dart';
import '../fall/fall_enable_session.dart';
import '../fall/fall_settings_controller.dart';
import '../l10n/strings_tr.dart';

/// Açık modu açmanın ekran kanalındaki ikinci adımı (Faz 7c-2, karar 1 ve 12).
/// Uyarı metni pencerede yazılıdır; "Anladım, aç" onayı `FallEnableSession`'a
/// EKRAN kanalından iletilir (ses kanalıyla başlayan açmayı ekran onaylayamaz).
///
/// - Varsayılan odak **"Vazgeç"**: yanlışlıkla Enter/çift dokunuşla açılmasın.
/// - TalkBack açıkken uyarıyı yalnızca TalkBack okur; kapalıyken TTS okur,
///   ikisi asla çakışmaz (karar 3).
/// - Dışarı dokunmak ya da geri = vazgeçmek: bekleyen açma iptal edilir.
/// - Dönen değer: onay denemesinin sonucu; vazgeçildiyse null.
Future<FallEnableConfirm?> showFallEnableDialog(
  BuildContext context, {
  required FallSettingsController controller,
  required FallEnableBegin begin,
  required FeedbackHub feedback,
}) async {
  final result = await showDialog<FallEnableConfirm>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FallEnableDialog(controller: controller, begin: begin, feedback: feedback),
  );
  if (result == null) controller.session.cancel();
  return result;
}

class _FallEnableDialog extends StatefulWidget {
  final FallSettingsController controller;
  final FallEnableBegin begin;
  final FeedbackHub feedback;

  const _FallEnableDialog({required this.controller, required this.begin, required this.feedback});

  @override
  State<_FallEnableDialog> createState() => _FallEnableDialogState();
}

class _FallEnableDialogState extends State<_FallEnableDialog> {
  bool _busy = false;
  bool _spoke = false;
  bool _started = false;

  String get _warning => widget.begin.fullText ? Tr.fallOpenWarningFull : Tr.fallOpenWarningShort;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // TalkBack açıkken metni TalkBack okur; TTS'i de çalıştırmak çift okuma olurdu.
    if (!MediaQuery.accessibleNavigationOf(context)) {
      _spoke = true;
      final note = widget.begin.gateBypassed ? '${Tr.fallGateBypassedNote}. ' : '';
      widget.feedback.say('$note$_warning', dedupe: false);
    }
  }

  @override
  void dispose() {
    if (_spoke) widget.feedback.queue.stopAll();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await widget.controller.session.confirm(FallEnableChannel.screen);
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    const buttonSize = WidgetStatePropertyAll(Size(64, 56));
    return AlertDialog(
      title: Semantics(header: true, child: const Text(Tr.fallOpenDialogTitle)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.begin.gateBypassed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  container: true,
                  child: const Text(
                    Tr.fallGateBypassedNote,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            Semantics(container: true, child: Text(_warning)),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          style: const ButtonStyle(minimumSize: buttonSize),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text(Tr.fallOpenDialogCancel),
        ),
        FilledButton(
          style: const ButtonStyle(minimumSize: buttonSize),
          onPressed: _busy ? null : _confirm,
          child: const Text(Tr.fallOpenDialogConfirm),
        ),
      ],
    );
  }
}
