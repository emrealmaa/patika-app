import 'dart:async';

import '../accessibility/announcement_queue.dart';
import '../accessibility/earcons.dart';
import '../accessibility/feedback_hub.dart';
import '../l10n/strings_tr.dart';
import 'sos_config.dart';
import 'sos_controller.dart';
import 'sos_delivery.dart';

/// SOS'un söylediklerini [FeedbackHub] üzerinden (kritik öncelik) ses + kısa
/// ses olarak verir. Metin kuruluşu statik yardımcılarda (testli).
///
/// "Gönderildi" yalnızca gönderim sonucu `sent` ise söylenir; "iletildi/ulaştı"
/// hiç kullanılmaz (teslim raporu yok).
class FeedbackSosAnnouncer implements SosAnnouncer {
  final FeedbackHub _feedback;

  /// Geri sayım sürerken mikrofonun "iptal" için açık kalmasını sağlar
  /// (her saniye çağrılır; zaten dinliyorsa hiçbir şey yapmaz).
  final void Function() _ensureListening;

  bool _introDone = true;

  FeedbackSosAnnouncer(this._feedback, {required void Function() ensureListening})
      : _ensureListening = ensureListening;

  Future<bool> _say(String text) =>
      _feedback.say(text, priority: AnnouncementPriority.critical, dedupe: false);

  void _fail(String text) =>
      _feedback.signal(FeedbackEvent.error, text: text, priority: AnnouncementPriority.critical);

  // --- ön kontrol ---------------------------------------------------------------

  @override
  void unsupported() => _fail(Tr.sosUnsupported);

  @override
  void noContacts({required bool offer112}) =>
      _fail(offer112 ? '${Tr.sosNoContacts}. ${Tr.sosOffer112}' : '${Tr.sosNoContacts}. ${Tr.sosNoContactsHint}');

  @override
  void noSmsPermission({required bool offer112}) => _fail(
      offer112 ? '${Tr.sosNoSmsPermission}. ${Tr.sosOffer112}' : Tr.sosNoSmsPermission);

  @override
  void noCallPermission() => _fail(Tr.sosNoCallPermission);

  @override
  void rateLimited() => _fail(Tr.sosRateLimited);

  // --- geri sayım ---------------------------------------------------------------

  @override
  void countdownStarted(SosSource source, Duration total) {
    _feedback.signal(FeedbackEvent.sosTick);
    _introDone = false;
    _say(source == SosSource.fall ? Tr.sosFallCountdownStart : Tr.sosCountdownStart).whenComplete(() {
      _introDone = true;
      _ensureListening();
    });
  }

  @override
  void tick(Duration remaining) {
    _feedback.signal(FeedbackEvent.sosTick);
    // Son 3 saniyede bip sıklaşır (saniyede iki).
    if (remaining.inSeconds <= 3) {
      Timer(const Duration(milliseconds: 500), () => _feedback.earcons.play(Earcon.sosTick));
    }
    // Giriş cümlesi bitmeden mikrofon açılmaz (kendi sesimizi duymasın).
    if (_introDone) _ensureListening();
  }

  @override
  void cancelled(SosCancelSource by) {
    _feedback.queue.stopAll();
    _feedback.signal(FeedbackEvent.success, text: Tr.sosCancelled, priority: AnnouncementPriority.critical);
  }

  @override
  void cancelTooLate() => _fail(Tr.sosTooLate);

  @override
  void sending(SosLocation location) {
    final text = switch (location) {
      SosLocation.included => Tr.sosSending,
      SosLocation.noPermission => Tr.sosSendingNoLocationPermission,
      SosLocation.unavailable => Tr.sosSendingNoLocation,
    };
    _feedback.signal(FeedbackEvent.understood, text: text, priority: AnnouncementPriority.critical);
  }

  // --- sonuçlar -----------------------------------------------------------------

  @override
  Future<void> smsResults(
    List<SosRecipientResult> results, {
    required SosLocation location,
    required SosCallTarget callTarget,
    required bool offer112,
  }) async {
    await _say(resultsText(results, callTarget: callTarget, offer112: offer112));
  }

  @override
  Future<void> calling112() async {
    await _say(Tr.sosCalling112);
  }

  @override
  void call112Failed(SosCallOutcome outcome) => _fail(switch (outcome) {
        SosCallOutcome.numberUnavailable => Tr.sosCall112NoNumber,
        SosCallOutcome.noPermission => Tr.sosCall112NoPermission,
        _ => Tr.sosCall112Failed,
      });

  @override
  Future<void> afterCall(SosReport report, {required List<SosRecipientResult> late}) async {
    final text = afterCallText(report, late);
    if (text.isNotEmpty) await _say(text);
  }

  @override
  void followUp({required bool sent}) => _feedback.signal(
        sent ? FeedbackEvent.success : FeedbackEvent.error,
        text: sent ? Tr.sosFollowUpSent : Tr.sosFollowUpFailed,
        priority: AnnouncementPriority.critical,
      );

  // --- metin kuruluşu (testli) ----------------------------------------------------

  /// SMS sonuçları, arama başlamadan. Örnekler:
  /// "Acil durum mesajı 2 kişiye gönderildi. Şimdi Ayşe aranıyor";
  /// "Gönderilemedi, 112'yi aramak için çift dokunun, yoksa Ayşe aranacak".
  static String resultsText(
    List<SosRecipientResult> results, {
    required SosCallTarget callTarget,
    required bool offer112,
  }) {
    final sent = results.where((r) => r.sent).length;
    final pending = results.where((r) => r.pending).length;
    final failed = results.length - sent - pending;
    final otherwise = callTarget.name == null ? '' : ', yoksa ${callTarget.name} aranacak';

    // Hiçbiri gitmedi (bekleyen de yok): kısa ve doğrudan.
    if (results.isNotEmpty && sent == 0 && pending == 0) {
      return offer112 ? '${Tr.sosNoneSent}, ${Tr.sosOffer112}$otherwise' : _withCall(Tr.sosNoneSent, callTarget);
    }

    final parts = <String>[
      if (sent > 0) Tr.sosSentTo(sent),
      if (failed > 0) Tr.sosNotSentTo(failed),
      if (pending > 0) Tr.sosWaitingFor(pending),
    ];
    if (offer112) {
      parts.add('${Tr.sosOffer112}$otherwise');
    } else {
      final call = _callSentence(callTarget);
      if (call != null) parts.add(call);
    }
    return parts.join('. ');
  }

  static String _withCall(String head, SosCallTarget target) {
    final call = _callSentence(target);
    return call == null ? head : '$head. $call';
  }

  static String? _callSentence(SosCallTarget target) {
    if (target.is112) return Tr.sosCalling112Now;
    if (target.name != null) return Tr.sosCallingContact(target.name!);
    return null;
  }

  /// Arama bittikten sonra: yalnızca sonradan belli olan sonuçlar ve arama sorunu.
  static String afterCallText(SosReport report, List<SosRecipientResult> late) {
    final parts = <String>[
      for (final r in late)
        r.pending
            ? Tr.sosWaitingFor(1)
            : (r.sent ? Tr.sosLateSent(r.contact.name) : Tr.sosLateFailed(r.contact.name)),
      switch (report.call.outcome) {
        SosCallOutcome.failed => report.call.target.is112 ? Tr.sosCall112Failed : Tr.sosCallFailed,
        SosCallOutcome.noPermission =>
          report.call.target.is112 ? Tr.sosCall112NoPermission : Tr.sosCallNoPermission,
        SosCallOutcome.numberUnavailable => Tr.sosCall112NoNumber,
        _ => '',
      },
    ].where((p) => p.isNotEmpty).toList();
    return parts.join('. ');
  }
}
