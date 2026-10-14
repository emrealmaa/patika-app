import '../../l10n/strings_tr.dart';
import '../../settings/message_apps.dart';
import '../../settings/settings.dart';
import '../../settings/settings_store.dart';
import '../action_result.dart';
import '../voice_intent_classifier.dart' show messageAppsListEntity, parseMessageAppEntity;

/// AYAR niyeti: "daha hızlı konuş", "kısa anlat", "titreşimi azalt" gibi
/// sesli ayar değişiklikleri. Sonuç mesajı yeni değeri söylüyor - hız
/// değişikliğinde bu cümle zaten yeni hızda okunuyor (kendi önizlemesi).
class SettingsHandler {
  final SettingsStore _store;

  SettingsHandler(this._store);

  Future<ActionResult> handle(String? entity) async {
    if (entity == messageAppsListEntity) return ActionResult.ok(describeMessageApps(_store.value.messageApps));
    final appToggle = parseMessageAppEntity(entity);
    if (appToggle != null) return _toggleApp(appToggle.$1, on: appToggle.$2);

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

  /// "WhatsApp bildirimlerini kapat/aç". WhatsApp kişisel ve iş birlikte.
  /// Hepsi kapanırsa bunu söyler: "mesaj duyuruları kapalı".
  Future<ActionResult> _toggleApp(MessageApp app, {required bool on}) async {
    final group = app == MessageApp.whatsapp
        ? const {MessageApp.whatsapp, MessageApp.whatsappBusiness}
        : {app};
    final before = _store.value.messageApps;
    final after = on ? {...before, ...group} : before.difference(group);
    await _store.update(_store.value.copyWith(messageApps: after));
    final name = Tr.messageAppName(app.name);
    if (after.isEmpty) return ActionResult.ok(Tr.messageAppsAllOff);
    return ActionResult.ok(on ? Tr.messageAppOn(name) : Tr.messageAppOff(name));
  }
}

/// "Mesajları okunan uygulamalar: SMS, WhatsApp" ya da hepsi kapalıysa uyarı.
String describeMessageApps(Set<MessageApp> apps) {
  if (apps.isEmpty) return Tr.messageAppsAllOff;
  return Tr.messageAppsList([
    for (final a in MessageApp.values)
      if (apps.contains(a)) Tr.messageAppName(a.name),
  ]);
}
