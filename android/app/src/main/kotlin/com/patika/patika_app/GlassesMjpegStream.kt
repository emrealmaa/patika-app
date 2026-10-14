package com.patika.patika_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.net.HttpURLConnection
import java.net.URL

/**
 * Gözlük MJPEG akışını GÖZLÜK AĞI ÜZERİNDEN okur (kanal `patika/glasses_mjpeg`,
 * EventChannel). Bağlantı `GlassesNetwork.network.openConnection` ile açılır:
 * istek yalnızca gözlüğün SoftAP'ından gider, uygulamanın diğer istekleri
 * varsayılan ağda (mobil veri) kalır. Dart'ın `HttpClient`'ı belirli bir ağa
 * bağlanamadığı için bu iş native'de.
 *
 * Baytlar AYRIŞTIRILMADAN Dart'a gider (`lib/camera/mjpeg_parser.dart`):
 * önce `{"type":"header","contentType":...}`, sonra `{"type":"chunk","bytes":...}`.
 * Akış bitince/koparsa `endOfStream`; ağ yoksa `error("noNetwork")`.
 * Dart dinlemeyi iptal edince bağlantı kapatılır.
 *
 * Geri basınç: okuma bloklayıcı; Dart yavaşsa olaylar ana iş parçacığında
 * birikebilir. Tazelik Dart'ta (`LatestFrame`) sağlanır; gerçek akışta
 * birikme ölçülecek (CLAUDE.md "Bekleyen telefon testleri").
 *
 * Düz HTTP: `res/xml/network_security_config.xml` yalnızca gözlük SoftAP
 * adresine (192.168.4.1) izin verir; başka adres engellenir.
 */
class GlassesMjpegStream(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PatikaGlassesMjpeg"
        private const val CHANNEL = "patika/glasses_mjpeg"
        private const val CHUNK = 16 * 1024
        private const val TIMEOUT_MS = 5000
    }

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var connection: HttpURLConnection? = null

    fun attach(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val url = (arguments as? Map<*, *>)?.get("url") as? String
        val network = GlassesNetwork.get(context).network
        if (url == null || network == null) {
            events.error("noNetwork", "Gözlük ağı bağlı değil", null)
            return
        }
        val thread = Thread {
            try {
                val conn = network.openConnection(URL(url)) as HttpURLConnection
                connection = conn
                conn.connectTimeout = TIMEOUT_MS
                conn.readTimeout = TIMEOUT_MS
                conn.connect()
                val contentType = conn.contentType
                main.post { events.success(mapOf("type" to "header", "contentType" to contentType)) }
                conn.inputStream.use { input ->
                    val buffer = ByteArray(CHUNK)
                    while (!Thread.currentThread().isInterrupted) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        val bytes = buffer.copyOf(n)
                        main.post { events.success(mapOf("type" to "chunk", "bytes" to bytes)) }
                    }
                }
            } catch (e: Exception) {
                // Adres günlüğe yazılmaz; yalnızca hata türü.
                Log.i(TAG, "Akış bitti: ${e.javaClass.simpleName}")
            } finally {
                connection?.disconnect()
                connection = null
                if (!Thread.currentThread().isInterrupted) main.post { events.endOfStream() }
            }
        }
        worker = thread
        thread.start()
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        worker?.interrupt()
        worker = null
        try {
            connection?.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Kapatılamadı: ${e.javaClass.simpleName}")
        }
        connection = null
    }
}
