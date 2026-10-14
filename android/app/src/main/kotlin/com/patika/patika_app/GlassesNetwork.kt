package com.patika.patika_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Gözlüğün Wi-Fi SoftAP'ına UYGULAMAYA ÖZEL bağlantı (kanal `patika/glasses_wifi`).
 *
 * SoftAP internetsizdir. Telefon ona sıradan bir Wi-Fi gibi bağlansaydı
 * Android varsayılan ağı değiştirip mobil veriyi bırakabilirdi; Routes/Places
 * ve diğer internet istekleri kırılırdı. Bunun yerine
 * `ConnectivityManager.requestNetwork` + `WifiNetworkSpecifier` (API 29+):
 * sistem ağı yalnızca bu uygulamaya verir, varsayılan ağ DEĞİŞMEZ.
 *
 * **`bindProcessToNetwork` bilerek kullanılmıyor:** süreci bu ağa bağlar ve
 * uygulamanın internet isteklerini (Google, Gemini) internetsiz ağa yollar.
 * `test/glasses_wifi_test.dart` bu dosyada geçmediğini kilitler. Gözlüğe
 * yapılacak istekler (MJPEG, WebSocket) [network] üzerinden
 * (`network.openConnection` / `network.socketFactory`) yapılacak; Dart'ın
 * `HttpClient`'ı belirli bir ağa bağlanamaz.
 *
 * Durumlar Dart'a `onState` çağrısıyla gider: `requesting`, `connected`,
 * `lost`, `unavailable` (+ neden), `userDeclined`, `idle`.
 *
 * `onUnavailable` zaman aşımı verilmeden istendiği için yalnızca sistem onay
 * penceresi kapanınca gelir: kullanıcı reddetti ya da pencere "ağ bulunamadı"
 * deyip kapandı. Android bu ikisini ayırmıyor; ikisi de `userDeclined`.
 *
 * İstek, [disconnect] çağrılana kadar açık kalır: ağ kopunca (`onLost`) sistem
 * yeniden bulursa `onAvailable` tekrar gelir (yeniden onay penceresi açmadan
 * mı - cihazda doğrulanacak, bkz. CLAUDE.md "Bekleyen telefon testleri").
 */
class GlassesNetwork private constructor(private val context: Context) {

    companion object {
        private const val TAG = "PatikaGlassesNetwork"
        private const val CHANNEL = "patika/glasses_wifi"

        @Volatile
        private var instance: GlassesNetwork? = null

        /**
         * Süreç başına tek örnek: etkinlik yeniden oluşturulunca
         * `configureFlutterEngine` tekrar çağrılır; açık ağ isteği ve
         * [network] kaybolmasın (motor da süreç boyunca yaşıyor).
         */
        fun get(context: Context): GlassesNetwork =
            instance ?: synchronized(this) {
                instance ?: GlassesNetwork(context.applicationContext).also { instance = it }
            }
    }

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    /** Şu an bağlı gözlük ağı (yoksa null). Madde 2'de MJPEG bunu kullanacak. */
    @Volatile
    var network: Network? = null
        private set

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "support" -> result.success(support())
                    "connect" -> {
                        val ssid = call.argument<String>("ssid")
                        val passphrase = call.argument<String>("passphrase")
                        result.success(null)
                        connect(ssid, passphrase)
                    }
                    "disconnect" -> {
                        disconnect()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * `supported`: API 29+ (`WifiNetworkSpecifier`). `nearbyPermission`:
     * Android 13+'ta NEARBY_WIFI_DEVICES çalışma zamanı izni gerekir; altında
     * bu izin yoktur (permission_handler orada "reddedildi" döndürüyor, bu
     * yüzden Dart yalnızca burası true derse ister).
     */
    private fun support(): Map<String, Boolean> = mapOf(
        "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
        "nearbyPermission" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU),
    )

    private fun connect(ssid: String?, passphrase: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.i(TAG, "WifiNetworkSpecifier için Android 10+ gerekiyor (API ${Build.VERSION.SDK_INT})")
            emit("unavailable", "unsupported")
            return
        }
        if (ssid.isNullOrEmpty()) {
            emit("unavailable", "error")
            return
        }
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifi != null && !wifi.isWifiEnabled) {
            emit("unavailable", "wifiOff")
            return
        }
        release()
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            val specifier = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
                if (!passphrase.isNullOrEmpty()) setWpa2Passphrase(passphrase)
            }.build()
            // İnternet yeteneği bilerek kaldırılıyor: SoftAP internetsiz.
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(n: Network) {
                    network = n
                    emit("connected")
                }

                override fun onLost(n: Network) {
                    if (network == n) network = null
                    emit("lost")
                }

                override fun onUnavailable() {
                    network = null
                    callback = null
                    emit("userDeclined")
                }
            }
            callback = cb
            emit("requesting")
            cm.requestNetwork(request, cb)
        } catch (e: Exception) {
            // Geçersiz SSID/parola (IllegalArgumentException) ya da izin
            // (SecurityException). Ayrıntı (SSID/parola) günlüğe yazılmaz.
            Log.w(TAG, "Ağ isteği başarısız: ${e.javaClass.simpleName}")
            callback = null
            emit("unavailable", "error")
        }
    }

    private fun disconnect() {
        release()
        emit("idle")
    }

    private fun release() {
        val cb = callback ?: return
        callback = null
        network = null
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(cb)
        } catch (e: Exception) {
            Log.w(TAG, "Ağ isteği bırakılamadı: ${e.javaClass.simpleName}")
        }
    }

    /** Geri çağrılar ConnectivityManager iş parçacığında gelir; kanal ana iş parçacığında. */
    private fun emit(state: String, reason: String? = null) {
        main.post {
            channel?.invokeMethod("onState", mapOf("state" to state, "reason" to reason))
        }
    }
}
