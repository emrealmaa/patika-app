import 'dart:async';

import 'package:flutter/foundation.dart';

import '../navigation/guidance_engine.dart' show PositionFix;
import '../platform/direct_actions.dart';
import 'emergency_contacts.dart';
import 'emergency_number.dart';
import 'sos_config.dart';
import 'sos_message.dart';

/// SOS başlamadan önce yapılan ön kontrol. `ready` dışındakiler geri sayım
/// BAŞLAMADAN söylenir: kullanıcı boşuna 7 sn beklemesin.
enum SosPreflight {
  ready,

  /// `play` derlemesi ya da doğrudan eylem yok: SOS desteklenmiyor.
  unsupported,

  /// Acil kişi yok (ve 112 kullanılamıyor).
  noContacts,

  /// SMS izni yok.
  noSmsPermission,

  /// Yalnızca 112 aranacaktı (kişi yok) ama arama izni yok.
  noCallPermission,
}

class SosRequest {
  final SosSource source;
  final DateTime time;

  /// Geri sayım bittiğinde elde olan konum; yoksa null (konumsuz gider).
  final PositionFix? fix;

  /// Ayar açık VE kaynak izin veriyorsa 112 **kendiliğinden** aranabilir.
  final bool allow112;

  const SosRequest({required this.source, required this.time, this.fix, required this.allow112});
}

class SosRecipientResult {
  final EmergencyContact contact;
  final SmsSendStatus status;

  /// Sonuç henüz gelmedi (operatör yanıtı bekleniyor); [status] geçici.
  final bool pending;

  const SosRecipientResult(this.contact, this.status, {this.pending = false});

  /// `sent`: mesaj operatöre ulaştı. Karşı tarafa **ulaştığı** anlamına
  /// GELMEZ (teslim raporu yok); "iletildi" denmez.
  bool get sent => status == SmsSendStatus.sent && !pending;
}

/// Tüm SMS'lerin aynı anda gönderimi. Sonuçlar geldikçe dolar; [results]
/// her an anlık görüntüdür (bitmeyenler `pending`).
class SosSmsBatch {
  final List<EmergencyContact> contacts;
  final List<SmsSendStatus?> _statuses;
  final Completer<void> _done = Completer<void>();
  int _remaining;

  SosSmsBatch(this.contacts)
      : _statuses = List<SmsSendStatus?>.filled(contacts.length, null),
        _remaining = contacts.length {
    if (contacts.isEmpty) _done.complete();
  }

  void record(int index, SmsSendStatus status) {
    if (_statuses[index] != null) return;
    _statuses[index] = status;
    if (--_remaining == 0 && !_done.isCompleted) _done.complete();
  }

  /// Hepsinin sonucu geldiğinde tamamlanır.
  Future<void> get settled => _done.future;

  bool get hasPending => _remaining > 0;

  List<SosRecipientResult> get results => [
        for (var i = 0; i < contacts.length; i++)
          SosRecipientResult(
            contacts[i],
            _statuses[i] ?? SmsSendStatus.timeout,
            pending: _statuses[i] == null,
          ),
      ];
}

enum SosCallOutcome {
  /// Aranacak kimse yoktu ya da arama seçilmedi.
  notAttempted,
  placed,
  failed,
  noPermission,

  /// 112 aranacaktı ama numara kullanılamıyor (release dışı ve test numarası yok).
  numberUnavailable,
}

/// Aranması **planlanan** kişi/numara. Arama başlamadan önce söylenebilsin
/// diye (arama başlayınca TTS araya girmez).
class SosCallTarget {
  /// Aranacak kişinin adı; 112 ise null ve [is112] true; hiç arama yoksa ikisi de boş.
  final String? name;
  final bool is112;

  const SosCallTarget({this.name, this.is112 = false});

  static const none = SosCallTarget();

  bool get isNone => name == null && !is112;
}

class SosCallResult {
  final SosCallOutcome outcome;
  final SosCallTarget target;

  const SosCallResult(this.outcome, [this.target = SosCallTarget.none]);

  static const none = SosCallResult(SosCallOutcome.notAttempted);

  bool get placed => outcome == SosCallOutcome.placed;
}

class SosReport {
  final List<SosRecipientResult> sms;
  final SosCallResult call;
  final bool locationIncluded;

  const SosReport({required this.sms, required this.call, required this.locationIncluded});

  int get smsSent => sms.where((r) => r.sent).length;
  bool get anySmsSent => smsSent > 0;
  bool get allSmsSent => sms.isNotEmpty && smsSent == sms.length;

  /// SOS en az bir kanaldan gerçekten çıktı (60 sn sınırı yalnızca bunu sayar).
  bool get delivered => anySmsSent || call.placed;
}

/// SMS ve arama izinlerinin **yoklaması** (istemez): acil durumda izin
/// penceresi açılmaz. İzinler acil kişi kurulumunda istenir.
abstract class SosPermissions {
  Future<bool> hasSms();
  Future<bool> hasCall();
}

/// SOS'un gerçek gönderimi. Denetleyici zamanlamayı ve söylenecekleri
/// yönetir; SMS/arama burada. Hiçbiri hata fırlatmaz.
abstract class SosDelivery {
  Future<SosPreflight> preflight({required bool allow112});

  /// Tüm acil kişilere SMS'leri BAŞLATIR ve hemen döner; sonuçlar batch'te dolar.
  Future<SosSmsBatch> startSms(SosRequest request);

  /// Sonra yapılacak TEK aramanın hedefi: [allow112] ise 112, değilse ilk kişi,
  /// hiçbiri yoksa [SosCallTarget.none].
  Future<SosCallTarget> plannedCall({required bool allow112});

  /// Planlanan aramayı yapar.
  Future<SosCallResult> placeCall({required bool allow112});

  /// Konumsuz gönderilen SOS'un tek takip SMS'i. En az biri gittiyse true.
  Future<bool> sendFollowUp({required DateTime time, required PositionFix fix});

  /// Kullanıcı onaylı 112 araması ("112'yi aramak için çift dokunun").
  Future<SosCallOutcome> call112();
}

/// `direct` derlemesi: [DirectActions] ile gerçek SMS/arama. `play`
/// derlemesinde [DirectActions.isAvailable] false döner ve [preflight]
/// `unsupported` verir (Seçenek 2: bu sürümde SOS yok).
class DirectSosDelivery implements SosDelivery {
  final DirectActions _direct;
  final EmergencyContactStore _contacts;
  final SosPermissions _permissions;
  final EmergencyNumber _emergency;

  DirectSosDelivery({
    required DirectActions direct,
    required EmergencyContactStore contacts,
    required SosPermissions permissions,
    EmergencyNumber emergency = const EmergencyNumber(),
  })  : _direct = direct,
        _contacts = contacts,
        _permissions = permissions,
        _emergency = emergency;

  @override
  Future<SosPreflight> preflight({required bool allow112}) async {
    if (!await _direct.isAvailable()) return SosPreflight.unsupported;
    final contacts = await _contacts.readAll();
    if (contacts.isEmpty) {
      if (!allow112 || !_emergency.canDial) return SosPreflight.noContacts;
      return await _permissions.hasCall() ? SosPreflight.ready : SosPreflight.noCallPermission;
    }
    if (!await _permissions.hasSms()) return SosPreflight.noSmsPermission;
    return SosPreflight.ready;
  }

  @override
  Future<SosSmsBatch> startSms(SosRequest request) async {
    final contacts = await _contacts.readAll();
    final batch = SosSmsBatch(contacts);
    if (contacts.isEmpty) return batch;
    if (!await _permissions.hasSms()) {
      for (var i = 0; i < contacts.length; i++) {
        batch.record(i, SmsSendStatus.unavailable);
      }
      return batch;
    }
    final body = SosMessage.initial(time: request.time, fix: request.fix);
    for (var i = 0; i < contacts.length; i++) {
      unawaited(_sendOne(contacts[i], body).then((status) => batch.record(i, status)));
    }
    return batch;
  }

  @override
  Future<SosCallTarget> plannedCall({required bool allow112}) async {
    if (allow112) return const SosCallTarget(is112: true);
    final contacts = await _contacts.readAll();
    if (contacts.isEmpty) return SosCallTarget.none;
    return SosCallTarget(name: contacts.first.name);
  }

  @override
  Future<SosCallResult> placeCall({required bool allow112}) async {
    final target = await plannedCall(allow112: allow112);
    if (target.isNone) return SosCallResult.none;
    final String number;
    if (target.is112) {
      final n = _emergency.dialNumber;
      if (n == null) return SosCallResult(SosCallOutcome.numberUnavailable, target);
      number = n;
    } else {
      number = (await _contacts.readAll()).first.number;
    }
    if (!await _permissions.hasCall()) return SosCallResult(SosCallOutcome.noPermission, target);
    final ok = await _dial(number);
    return SosCallResult(ok ? SosCallOutcome.placed : SosCallOutcome.failed, target);
  }

  @override
  Future<bool> sendFollowUp({required DateTime time, required PositionFix fix}) async {
    final contacts = await _contacts.readAll();
    if (contacts.isEmpty || !await _permissions.hasSms()) return false;
    final body = SosMessage.followUp(time: time, fix: fix);
    final results = await Future.wait(contacts.map((c) => _sendOne(c, body)));
    return results.any((s) => s == SmsSendStatus.sent);
  }

  @override
  Future<SosCallOutcome> call112() async {
    final number = _emergency.dialNumber;
    if (number == null) return SosCallOutcome.numberUnavailable;
    if (!await _permissions.hasCall()) return SosCallOutcome.noPermission;
    return await _dial(number) ? SosCallOutcome.placed : SosCallOutcome.failed;
  }

  Future<SmsSendStatus> _sendOne(EmergencyContact contact, String body) async {
    try {
      return await _direct.sendSms(contact.number, body);
    } catch (e) {
      debugPrint('[SOS] SMS hatası: ${e.runtimeType}');
      return SmsSendStatus.failed;
    }
  }

  Future<bool> _dial(String number) async {
    try {
      return await _direct.call(number);
    } catch (e) {
      debugPrint('[SOS] arama hatası: ${e.runtimeType}');
      return false;
    }
  }
}
