import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patika_app/fall/fall_consent_store.dart';

/// Faz 7c-2: bu cihazdaki açık mod onayı. Gerçek depo `noBackupFilesDir`'de bir
/// dosya (`FallOpenConsentStorage.kt`); burada Dart tarafı kanal hatalarında
/// GÜVENLİ yöne (onay yok / kaydedilemedi) düşüyor mu denenir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('patika/fall_consent');

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
  }

  group('MethodChannelFallConsentStore', () {
    test('granted / grant / revoke kanal çağrılarına eşlenir', () async {
      final calls = <String>[];
      var present = false;
      mock((call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'granted':
            return present;
          case 'grant':
            present = true;
            return true;
          case 'revoke':
            present = false;
            return null;
        }
        return null;
      });
      final store = MethodChannelFallConsentStore();
      expect(await store.granted(), isFalse);
      expect(await store.grant(), isTrue);
      expect(await store.granted(), isTrue);
      await store.revoke();
      expect(await store.granted(), isFalse);
      expect(calls, ['granted', 'grant', 'granted', 'revoke', 'granted']);
    });

    test('okuma hatası ya da boş cevap = onay YOK (güvenli yön)', () async {
      mock((call) async => throw PlatformException(code: 'x'));
      expect(await MethodChannelFallConsentStore().granted(), isFalse);
      mock((call) async => null);
      expect(await MethodChannelFallConsentStore().granted(), isFalse);
    });

    test('yazma hatası ya da false cevap = kaydedilemedi (açık mod açılmaz)', () async {
      mock((call) async => throw PlatformException(code: 'x'));
      expect(await MethodChannelFallConsentStore().grant(), isFalse);
      mock((call) async => false);
      expect(await MethodChannelFallConsentStore().grant(), isFalse);
    });

    test('silme hatası uygulamayı durdurmaz', () async {
      mock((call) async => throw PlatformException(code: 'x'));
      await MethodChannelFallConsentStore().revoke();
    });

    test('kanal hiç bağlı değilse (MissingPlugin) onay yok, kaydedilemedi', () async {
      expect(await MethodChannelFallConsentStore().granted(), isFalse);
      expect(await MethodChannelFallConsentStore().grant(), isFalse);
    });
  });

  group('MemoryFallConsentStore', () {
    test('varsayılan YOK; grant/revoke; failGrant başarısız olur', () async {
      final store = MemoryFallConsentStore();
      expect(await store.granted(), isFalse);
      expect(await store.grant(), isTrue);
      expect(await store.granted(), isTrue);
      await store.revoke();
      expect(await store.granted(), isFalse);
      store.failGrant = true;
      expect(await store.grant(), isFalse);
      expect(await store.granted(), isFalse);
    });
  });
}
