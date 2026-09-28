import 'dart:async';

import '../../l10n/strings_tr.dart';
import '../../platform/direct_actions.dart';
import '../../sos/emergency_contacts.dart';
import '../../voice/dialog_manager.dart';
import '../../voice/dialogs/emergency_contact_flow.dart';
import '../action_result.dart';
import '../contact_resolver.dart';

/// ACİL_KİŞİ niyeti. Entity biçimi (sınıflandırıcı üretir):
/// - "ekle|X": X boşsa diyalog kimi ekleyeceğini sorar.
/// - "sil|X": X boşsa (ya da eşleşmezse) diyalog mevcut acil kişileri söyler.
/// - "liste": kayıtlı acil kişileri okur, diyalog gerekmez.
class EmergencyContactHandler {
  final ContactResolver _contacts;
  final EmergencyContactStore _store;
  final DialogManager? _dialogs;
  final DirectActions _direct;
  final Future<bool> Function() _ensureSmsPermission;

  EmergencyContactHandler({
    ContactResolver? contacts,
    required EmergencyContactStore store,
    DialogManager? dialogs,
    DirectActions direct = const NoDirectActions(),
    Future<bool> Function()? ensureSmsPermission,
  })  : _contacts = contacts ?? ContactResolver(),
        _store = store,
        _dialogs = dialogs,
        _direct = direct,
        _ensureSmsPermission = ensureSmsPermission ?? (() async => false);

  Future<ActionResult> handle(String? entity) async {
    final parts = (entity ?? '').split('|');
    final name = parts.length > 1 && parts[1].trim().isNotEmpty ? parts[1].trim() : null;
    switch (parts.first) {
      case 'ekle':
        return _start(EmergencyContactAddFlow(name, _contacts, _store, _direct, _ensureSmsPermission),
            'Acil kişi ekleme diyaloğu başladı');
      case 'sil':
        return _start(EmergencyContactRemoveFlow(name, _store), 'Acil kişi silme diyaloğu başladı');
      case 'liste':
        return _list();
      default:
        return ActionResult.fail(Tr.emergencyContactNotUnderstood);
    }
  }

  Future<ActionResult> _start(DialogFlow flow, String startedMessage) async {
    final dialogs = _dialogs;
    if (dialogs == null) return ActionResult.fail(Tr.emergencyContactNotUnderstood);
    // Diyalog dakikalar sürebilir; router'ı bekletmiyoruz. Sonucu diyalog
    // bitince AppState kaydedip duyuruyor (ARA/MESAJ ile aynı desen).
    unawaited(dialogs.start(flow));
    return ActionResult.handedOff(startedMessage);
  }

  Future<ActionResult> _list() async {
    final all = await _store.readAll();
    if (all.isEmpty) return ActionResult.ok(Tr.emergencyContactListEmpty);
    return ActionResult.ok(Tr.emergencyContactList([for (final c in all) c.name]));
  }
}
