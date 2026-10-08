import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın paket adı ve imza SHA-1'i (Google Cloud "Android uygulaması"
/// anahtar kısıtlaması için) ya da iOS'ta paket kimliği ("iOS uygulaması"
/// kısıtlaması; imza parmak izi yok).
class AppIdentity {
  /// Android'de paket adı, iOS'ta paket kimliği (bundle identifier).
  final String package;

  /// İki nokta yok, büyük harf; okunamadıysa null. iOS'ta hep null.
  final String? sha1;

  /// iOS kimliği mi: başlık adları buna göre seçilir.
  final bool ios;

  const AppIdentity(this.package, [this.sha1]) : ios = false;

  const AppIdentity.ios(this.package)
      : sha1 = null,
        ios = true;
}

abstract class AppIdentitySource {
  /// Okunamazsa (Android dışı, testler, imza okunamadı) null.
  Future<AppIdentity?> read();
}

/// Native kanal `patika/identity` (bkz. `AppIdentity.kt`, `AppIdentity.swift`). Başarılı sonuç
/// önbelleğe alınır; başarısızlık alınmaz (sonraki istekte yeniden denenir).
class MethodChannelAppIdentity implements AppIdentitySource {
  static const _channel = MethodChannel('patika/identity');
  AppIdentity? _cached;

  @override
  Future<AppIdentity?> read() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final map = await _channel.invokeMapMethod<String, String?>('get');
      final package = map?['package'];
      if (package == null || package.isEmpty) return null;
      return _cached = map?['platform'] == 'ios'
          ? AppIdentity.ios(package)
          : AppIdentity(package, map?['sha1']);
    } catch (e) {
      // Parmak izi ve anahtar günlüğe yazılmaz; yalnızca hata türü.
      debugPrint('[AppIdentity] okunamadı: ${e.runtimeType}');
      return null;
    }
  }
}

/// Testler ve sabit kimlik için.
class FixedAppIdentity implements AppIdentitySource {
  final AppIdentity? identity;

  const FixedAppIdentity(this.identity);

  @override
  Future<AppIdentity?> read() async => identity;
}

/// Android ya da iOS uygulama kısıtlamalı bir anahtarla yapılan REST
/// çağrısının gerektirdiği başlıklar. Kimlik yoksa boş: istek başlıksız gider
/// (anahtar kısıtlı değilse çalışır, kısıtlıysa 403 alır ve yedek akışa
/// düşülür). Google'da bir anahtar ya Android ya iOS kısıtlaması taşır: iOS
/// derlemesi kendi anahtarıyla derlenmeli.
Future<Map<String, String>> appRestrictionHeaders(AppIdentitySource? source) async {
  final identity = await source?.read();
  if (identity == null) return const {};
  if (identity.ios) return {'X-Ios-Bundle-Identifier': identity.package};
  return {
    'X-Android-Package': identity.package,
    if (identity.sha1 != null && identity.sha1!.isNotEmpty) 'X-Android-Cert': identity.sha1!,
  };
}
