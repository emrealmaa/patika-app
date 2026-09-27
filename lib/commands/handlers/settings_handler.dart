import '../../l10n/strings_tr.dart';
import '../../settings/settings.dart';
import '../../settings/settings_store.dart';
import '../action_result.dart';

/// AYAR niyeti: "daha hızlı konuş", "kısa anlat", "titreşimi azalt" gibi
/// sesli ayar değişiklikleri. Sonuç mesajı yeni değeri söylüyor - hız
/// değişikliğinde bu cümle zaten yeni hızda okunuyor (kendi önizlemesi).
class SettingsHandler {
  final SettingsStore _store;

  SettingsHandler(this._store);

  Future<ActionResult> handle(String? entity) async {
    final action = SettingAction.fromName(entity);
    if (action == null) return ActionResult.fail(Tr.unknownCommand);

    final before = _store.value;
    final after = before.apply(action);
    await _store.update(after);

    final (name, value) = switch (action) {
      SettingAction.speechFaster ||
      SettingAction.speechSlower => (Tr.speechRate, after.speechRateName),
      SettingAction.shorter || SettingAction.longer => (Tr.verbosity, after.verbosityName),
      SettingAction.hapticStronger ||
      SettingAction.hapticWeaker ||
      SettingAction.hapticOff => (Tr.hapticStrength, after.hapticName),
      SettingAction.notificationsMuteOn ||
      SettingAction.notificationsMuteOff => (Tr.muteNotifications, ''),
    };

    if (action == SettingAction.hapticOff) return ActionResult.ok(Tr.hapticOff);
    if (action == SettingAction.notificationsMuteOn) {
      return ActionResult.ok(Tr.notificationsMuted);
    }
    if (action == SettingAction.notificationsMuteOff) {
      return ActionResult.ok(Tr.notificationsUnmuted);
    }
    if (identical(before, after)) {
      return ActionResult.ok(Tr.settingUnchanged(name, value));
    }
    return ActionResult.ok(Tr.settingChanged(name, value));
  }
}
