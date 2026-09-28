package com.patika.patika_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Dart motorunun (BLE bağlantısı, bağlantı denetçisi, duyurular) ömrünü
 * etkinlikten AYIRAN ana etkinlik.
 *
 * Neden: varsayılan FlutterActivity kendi motorunu oluşturur ve etkinlik
 * yok edilince motoru da yok eder. Geri tuşu etkinliği kapattığında Dart
 * mantığı ölüyor ama foreground service ve "Patika gözlüğe bağlı"
 * bildirimi kalıyordu - kullanıcı sistemsizken bağlı sanıyordu (emülatörde
 * doğrulandı). Artık:
 *
 * - Motor ilk açılışta bir kez oluşturulup süreç boyunca önbellekte
 *   tutuluyor; etkinlik yok edilse de (sistem, "etkinlikleri tutma") yaşıyor.
 * - Geri tuşu etkinliği kapatmıyor, uygulamayı arka plana alıyor.
 * - Yalnızca etkinlik gerçekten sonlanırken (son uygulamalardan kaydırma)
 *   motor bilerek yok ediliyor ve servis de durduruluyor - bildirim hiçbir
 *   zaman ölü bir motor için "bağlı" demiyor.
 *
 * Motor Application.onCreate'te değil burada oluşturuluyor: süreç ekransız
 * başlatıldığında (örn. Hızlı Ayarlar karosu bağlanırken) uygulama kendi
 * kendine bağlanıp konuşmaya başlamasın.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "PatikaMainActivity"
        const val ENGINE_ID = "patika_main_engine"

        /** Hızlı Ayarlar karosundan (ListenTileService) gelen "dinle" talimatı. */
        const val ACTION_LISTEN = "com.patika.patika_app.LISTEN"
        private const val LAUNCH_CHANNEL = "patika/launch"

        /**
         * Dart'ın henüz almadığı talimat. Etkinlikte değil burada: talimat
         * etkinlik yeniden oluşturulsa da kaybolmasın. Dart ya "actionPending"
         * bildirimiyle ya da açılışta kendisi sorarak alır ve temizler.
         */
        @Volatile
        private var pendingAction: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Yapılandırma değişimiyle yeniden oluşturulan etkinlik aynı
        // talimatı ikinci kez işlemesin.
        if (savedInstanceState == null) handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(intent: Intent?) {
        if (intent?.action != ACTION_LISTEN) return
        pendingAction = "listen"
        // Dart zaten çalışıyorsa hemen haber ver; çalışmıyorsa (ilk açılış)
        // Dart hazır olunca consumePendingAction ile kendisi alacak.
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID) ?: return
        if (engine.dartExecutor.isExecutingDart) {
            MethodChannel(engine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
                .invokeMethod("actionPending", null)
        }
    }

    /**
     * Motor dışarıdan verildiği için üst sınıf eklentileri tekrar kaydetmez
     * (motor yapıcısı zaten kaydetti); burada sadece başlatma kanalı kuruluyor.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // applicationContext: motor etkinlikten uzun yaşıyor; arama/SMS arka
        // planda da (ekran kilitliyken) çalışabilmeli.
        DirectActions(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        NotificationAccess(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        AppIdentity(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        AudioModeProbe(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingAction" -> {
                        val action = pendingAction
                        pendingAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Önbellekteki motoru verir; yoksa oluşturup önbelleğe koyar. Dart kodu
     * burada BAŞLATILMIYOR: motor dışarıdan verildiğinde Flutter, etkinlik
     * bağlandıktan sonra (onStart) Dart'ı kendisi başlatıyor ve zaten
     * çalışıyorsa tekrar başlatmıyor. Etkinlikten önce başlasaydı açılıştaki
     * izin isteği "etkinlik yok" hatasıyla başarısız olurdu.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        // applicationContext: motor etkinlikten uzun yaşadığı için etkinliği
        // sızdırmasın. Eklentiler bu yapıcıda otomatik kaydediliyor
        // (configureFlutterEngine dışarıdan verilen motorda tekrar kaydetmiyor).
        val engine = FlutterEngine(context.applicationContext)
        cache.put(ENGINE_ID, engine)
        return engine
    }

    /** Dışarıdan verilen motor etkinlikle birlikte yok edilmez (açıkça). */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /**
     * Dart tarafı gezinme yığınının dibinde geri tuşuna basıldığında buraya
     * düşer. Etkinliği kapatmak yerine uygulamayı arka plana alıyoruz
     * (Android 12+ kök etkinlik davranışıyla aynı); bağlantı ve bildirim
     * sürmeye devam eder.
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun onDestroy() {
        // isFinishing: etkinlik gerçekten sonlanıyor (son uygulamalardan
        // kaydırma ya da açık finish). Değilse sistem geçici olarak yok
        // ediyordur (yapılandırma değişimi, bellek, "etkinlikleri tutma") -
        // o durumda motor yaşamaya devam etmeli.
        val finishing = isFinishing && !isChangingConfigurations
        super.onDestroy()
        if (finishing) shutDown()
    }

    /**
     * Uygulama tamamen kapanıyor: önce servis (bildirim ölü bir motor için
     * "bağlı" demesin), sonra motor. Servis manifest'teki stopWithTask ile de
     * duruyor; bu, görev kaldırılmadan sonlanma durumları için ek güvence.
     */
    private fun shutDown() {
        try {
            stopService(Intent(this, ForegroundService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "Servis durdurulamadı", e)
        }
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { engine ->
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
            engine.destroy()
        }
    }
}
