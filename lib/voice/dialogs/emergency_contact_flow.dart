import '../../commands/action_result.dart';
import '../../commands/intent.dart';
import '../../contacts/contact_matcher.dart';
import '../../l10n/strings_tr.dart';
import '../../platform/direct_actions.dart';
import '../../sos/emergency_contacts.dart';
import '../dialog_manager.dart';
import '../reply_parser.dart';
import 'recipient_flow.dart';

/// ACİL_KİŞİ "ekle": "Acil kişi ekle" -> "Kimi ekleyeyim?" -> "Ayşe" ->
/// (iki Ayşe varsa "hangisi?") -> "Ayşe Demir'i acil kişi olarak ekleyeyim
/// mi?" -> "evet" -> eklenir; `direct` derlemesinde SMS izni bu sırada
/// istenir (bkz. CLAUDE.md Faz 7 kararları madde 7) ve verilmişse **isteğe
/// bağlı** bir rıza SMS'i sorulur - kişiye bir Patika kullanıcısının onu
/// acil kişi olarak eklediği bildirilir.
///
/// Numara her zaman kişinin rehberdeki **ilk** numarası (diğer akışlarla
/// aynı kural, bkz. `CallHandler.dial`) - kopyası saklanır, kişi rehberden
/// silinse de SOS çalışsın diye (bkz. `EmergencyContact`).
class EmergencyContactAddFlow extends RecipientFlow {
  final EmergencyContactStore _store;
  final DirectActions _direct;
  final Future<bool> Function() _ensureSmsPermission;

  EmergencyContactAddFlow(
    super.spoken,
    super.contacts,
    this._store,
    this._direct,
    this._ensureSmsPermission,
  );

  @override
  PatikaIntent get intent => PatikaIntent.acilKisi;

  @override
  String get askNamePrompt => Tr.dialogWhoToAddEmergency;

  @override
  String notFoundPrompt(String spoken) =>
      Tr.dialogNotFound(RecipientFlow.acc(spoken), Tr.dialogWhoToAddEmergency);

  String get _confirmPrompt => Tr.dialogConfirmEmergencyAdd(RecipientFlow.acc(contact!.displayName));

  /// Onay adımından SONRAKİ, isteğe bağlı rıza-SMS'i sorusu adımındayız.
  bool _askingConsent = false;
  EmergencyContact? _added;

  @override
  Future<DialogStep> onContactChosen(ContactEntry contact) async {
    if (contact.phones.isEmpty) {
      return FinishStep(ActionResult.fail(Tr.contactNoNumber(contact.displayName)));
    }
    return AskStep(_confirmPrompt);
  }

  @override
  Future<DialogStep> onLaterReply(String text) async {
    if (_askingConsent) return _onConsentReply(text);
    switch (parseYesNo(text)) {
      case YesNo.yes:
        return _add();
      case YesNo.no:
        return const CancelStep();
      case YesNo.unknown:
        return unclear(Tr.dialogYesNoHint, _confirmPrompt);
    }
  }

  Future<DialogStep> _add() async {
    final c = contact!;
    final entry = EmergencyContact(c.displayName, c.phones.first);
    switch (await _store.add(entry)) {
      case EmergencyAddResult.duplicate:
        return FinishStep(ActionResult.fail(Tr.emergencyContactDuplicate(c.displayName)));
      case EmergencyAddResult.full:
        return FinishStep(ActionResult.fail(Tr.emergencyContactListFull));
      case EmergencyAddResult.added:
        _added = entry;
    }

    // SMS izni yalnızca "direct" derlemesinde, kurulum sırasında (SOS anında
    // değil) sesli açıklamayla istenir. `play`'de hiç istenmez.
    if (!await _direct.isAvailable()) {
      return FinishStep(ActionResult.ok(Tr.emergencyContactAdded(c.displayName)));
    }
    if (!await _ensureSmsPermission()) {
      return FinishStep(ActionResult.ok(
        Tr.emergencyContactAdded(c.displayName),
        detail: Tr.emergencyContactNoSmsPermissionDetail,
      ));
    }

    _askingConsent = true;
    resetUnclear();
    return AskStep(Tr.dialogConfirmConsentSms(RecipientFlow.dat(c.displayName)));
  }

  Future<DialogStep> _onConsentReply(String text) async {
    final added = _added!;
    switch (parseYesNo(text)) {
      case YesNo.yes:
        return FinishStep(await _sendConsent(added));
      case YesNo.no:
        return FinishStep(ActionResult.ok(Tr.emergencyContactAdded(added.name)));
      case YesNo.unknown:
        return unclear(Tr.dialogYesNoHint, Tr.dialogConfirmConsentSms(RecipientFlow.dat(added.name)));
    }
  }

  Future<ActionResult> _sendConsent(EmergencyContact added) async {
    SmsSendStatus status;
    try {
      status = await _direct.sendSms(added.number, Tr.emergencyConsentSmsBody);
    } catch (_) {
      status = SmsSendStatus.failed;
    }
    return ActionResult.ok(
      Tr.emergencyContactAdded(added.name),
      detail: status == SmsSendStatus.sent
          ? Tr.emergencyConsentSent(added.name)
          : Tr.emergencyConsentFailed(added.name),
    );
  }
}

enum _RemoveStage { name, choose, confirm }

/// ACİL_KİŞİ "sil": kayıtlı acil kişiler arasından (telefon rehberi değil)
/// bulanık eşleştirme ile ([ContactMatcher], en fazla 3 kişi olduğu için
/// basit). İsim yoksa ya da bulunamazsa mevcut kişiler söylenir.
class EmergencyContactRemoveFlow extends DialogFlow {
  final String? _spoken;
  final EmergencyContactStore _store;

  EmergencyContactRemoveFlow(this._spoken, this._store);

  @override
  PatikaIntent get intent => PatikaIntent.acilKisi;

  EmergencyContact? _target;
  List<EmergencyContact> _choices = const [];
  var _stage = _RemoveStage.name;
  int _unclear = 0;

  @override
  String? get entityLabel => _target?.name ?? _spoken;

  @override
  Future<DialogStep> begin() async {
    final all = await _store.readAll();
    if (all.isEmpty) return FinishStep(ActionResult.fail(Tr.emergencyContactListEmpty));
    final spoken = _spoken;
    if (spoken == null) {
      _stage = _RemoveStage.choose;
      _choices = all;
      return AskStep(_choicePrompt(all));
    }
    return _resolve(spoken, all);
  }

  @override
  Future<DialogStep> onReply(String text) async {
    switch (_stage) {
      case _RemoveStage.name:
        final all = await _store.readAll();
        if (all.isEmpty) return FinishStep(ActionResult.fail(Tr.emergencyContactListEmpty));
        return _resolve(text, all);
      case _RemoveStage.choose:
        final index = parseChoice(text, [for (final c in _choices) _asEntry(c)]);
        if (index == null) return _unclear2(Tr.dialogChoiceHint, _choicePrompt(_choices));
        return _chosen(_choices[index]);
      case _RemoveStage.confirm:
        switch (parseYesNo(text)) {
          case YesNo.yes:
            await _store.remove(_target!.key);
            return FinishStep(ActionResult.ok(Tr.emergencyContactRemoved(_target!.name)));
          case YesNo.no:
            return const CancelStep();
          case YesNo.unknown:
            return _unclear2(Tr.dialogYesNoHint, _confirmPrompt);
        }
    }
  }

  Future<DialogStep> _resolve(String spoken, List<EmergencyContact> all) async {
    const matcher = ContactMatcher();
    final entries = [for (final c in all) _asEntry(c)];
    switch (matcher.match(spoken, entries)) {
      case ContactFound(:final contact):
        return _chosen(_byKey(all, contact.id));
      case ContactAmbiguous(:final candidates):
        _stage = _RemoveStage.choose;
        _choices = [for (final e in candidates) _byKey(all, e.id)];
        _unclear = 0;
        return AskStep(_choicePrompt(_choices));
      case ContactNotFound():
      case ContactPermissionDenied():
        return FinishStep(ActionResult.fail(
          Tr.emergencyContactRemoveNotFound(spoken, all.map((c) => c.name).join(', ')),
        ));
    }
  }

  DialogStep _chosen(EmergencyContact c) {
    _target = c;
    _stage = _RemoveStage.confirm;
    _unclear = 0;
    return AskStep(_confirmPrompt);
  }

  String get _confirmPrompt => Tr.dialogConfirmEmergencyRemove(RecipientFlow.acc(_target!.name));

  String _choicePrompt(List<EmergencyContact> choices) =>
      Tr.dialogChoose([for (final c in choices) c.name]);

  DialogStep _unclear2(String hint, String prompt) {
    if (++_unclear >= RecipientFlow.maxUnclear) return const CancelStep(Tr.dialogNotUnderstood);
    return AskStep('$hint $prompt');
  }

  static ContactEntry _asEntry(EmergencyContact c) => ContactEntry(c.key, c.name, [c.number]);
  static EmergencyContact _byKey(List<EmergencyContact> all, String key) =>
      all.firstWhere((c) => c.key == key);
}
