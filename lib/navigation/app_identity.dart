import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uygulamanın paket adı ve imza SHA-1'i (Google Cloud "Android uygulaması"
/// anahtar kısıtlaması için).
class AppIdentity {
  final String package;

  /// İki nokta yok, büyük harf; okunamadıysa null.
  final String? sha1;

  const AppIdentity(this.package, [this.sha1]);
}

abstract class AppIdentitySource {
  /// Okunamazsa (Android dışı, testler, imza okunamadı) null.
  Future<AppIdentity?> read();
}

/// Native kanal `patika/identity` (bkz. `AppIdentity.kt`). Başarılı sonuç
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
      return _cached = AppIdentity(package, map?['sha1']);
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

/// Android uygulama kısıtlamalı bir anahtarla yapılan REST çağrısının
/// gerektirdiği başlıklar. Kimlik yoksa boş: istek başlıksız gider (anahtar
/// kısıtlı değilse çalışır, kısıtlıysa 403 alır ve yedek akışa düşülür).
Future<Map<String, String>> androidRestrictionHeaders(AppIdentitySource? source) async {
  final identity = await source?.read();
  if (identity == null) return const {};
  return {
    'X-Android-Package': identity.package,
    if (identity.sha1 != null && identity.sha1!.isNotEmpty) 'X-Android-Cert': identity.sha1!,
  };
}
