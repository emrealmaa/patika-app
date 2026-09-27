import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/accessibility/announcement_queue.dart';
import 'package:patika_app/accessibility/feedback_hub.dart';
import 'package:patika_app/permissions/permission_explainer.dart';
import 'package:patika_app/settings/settings.dart';

import 'fakes.dart';

void main() {
  group('PermissionExplainer.ensureNotificationAccess', () {
    late FakeSpeechOutput tts;
    late FeedbackHub feedback;
    late PermissionExplainer permissions;
    late FakeNotificationAccess access;

    setUp(() {
      tts = FakeSpeechOutput();
      feedback = FeedbackHub(
        queue: AnnouncementQueue(tts),
        haptics: FakeHaptics(),
        earcons: FakeEarcons(),
        settings: () => const Settings(),
      );
      permissions = PermissionExplainer(feedback);
      access = FakeNotificationAccess();
    });

    test('zaten açıksa hiçbir şey sormadan true döner', () {
      fakeAsync((async) {
        access.enabled = true;
        bool? result;
        permissions.ensureNotificationAccess(access, 'açıklama').then((r) => result = r);
        async.flushMicrotasks();

        expect(result, isTrue);
        expect(tts.spoken, isEmpty);
        expect(access.openSettingsCalls, 0);
      });
    });

    test('kapalıysa önce açıklar, sonra ayarları açar, false döner', () {
      fakeAsync((async) {
        access.enabled = false;
        bool? result;
        permissions.ensureNotificationAccess(access, 'açıklama').then((r) => result = r);
        async.flushMicrotasks();
        expect(tts.spoken, ['açıklama']);

        tts.finishCurrent();
        async.flushMicrotasks();

        expect(access.openSettingsCalls, 1);
        expect(result, isFalse, reason: 'ayar ekranından dönüşte durum ayrıca kontrol edilmeli');
      });
    });
  });
}
