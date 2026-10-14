/// Gözlükle WebSocket üzerinden ses ve kontrol kanalı (ble_protocol.md §7).
///
/// **YAZILMADI - paket onayı bekliyor.** Dart'ta WebSocket istemcisi
/// (`dart:io` `WebSocket`) belirli bir ağa (gözlük SoftAP'ı) bağlanamaz;
/// varsayılan ağdan (mobil veri) gitmeye çalışır. Seçenekler:
/// 1. Kotlin tarafında `GlassesNetwork.network.socketFactory` ile bir
///    WebSocket istemcisi: Android'de yerleşik istemci yok, OkHttp gibi bir
///    bağımlılık gerekir (Apache-2.0).
/// 2. `web_socket_channel` (BSD-3) - yine ağ seçemez, tek başına yetmez.
/// Proje kuralı: yeni paket kurulmadan önce kullanıcı onayı. Onay gelene kadar
/// yalnızca arayüz var; her çağrı [UnimplementedError] fırlatır.
abstract class GlassesControlSocket {
  Future<void> connect(Uri uri);
  Stream<List<int>> get audio;
  Future<void> send(String message);
  Future<void> close();
}

class UnimplementedGlassesControlSocket implements GlassesControlSocket {
  const UnimplementedGlassesControlSocket();

  static const _why = 'Gözlük WebSocket kanalı yazılmadı: paket onayı bekliyor '
      '(bkz. lib/camera/glasses_control_socket.dart)';

  @override
  Future<void> connect(Uri uri) => throw UnimplementedError(_why);

  @override
  Stream<List<int>> get audio => throw UnimplementedError(_why);

  @override
  Future<void> send(String message) => throw UnimplementedError(_why);

  @override
  Future<void> close() => throw UnimplementedError(_why);
}
