package com.patika.patika_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Düşme algılama (Faz 7c) için ivmeölçer akışı. `sensors_plus` yerine kendi
 * kanalımız (yeni bağımlılık yok, Faz 7c kararı 4).
 *
 * - Kanal `patika/motion`: `available` (ivmeölçer var mı).
 * - Olay kanalı `patika/motion_events`: dinlenirken sensör açık, dinleme
 *   bitince kapalı. Dart tarafı yalnızca düşme modu kapalı değilken dinler.
 *
 * Yalnızca `TYPE_ACCELEROMETER` (yerçekimi dahil), ~50 Hz. 200 Hz altı olduğu
 * için `HIGH_SAMPLING_RATE_SENSORS` izni gerekmez. Jiroskop yok: yön değişimi
 * yerçekimi vektöründen hesaplanıyor (telefon testinde yeterliliği ölçülecek).
 *
 * Örnekler [BATCH_MS]'lik paketlerle gönderilir: `DoubleArray`
 * `[t_ms, x, y, z, t_ms, x, y, z, ...]`, eksenler m/s². Zaman sensör olayının
 * kendi zamanı (açılıştan beri, monoton; duvar saati değil), böylece Dart'taki
 * kesinti tespiti olay kanalının gecikmesinden etkilenmez.
 *
 * **Wakelock yok (bilinçli):** ekran kapalıyken CPU uyursa örnekler kesilir.
 * Dart tarafı bunu "kesinti" olarak sayar; gerçek cihazda ne sıklıkla olduğu
 * telefon testinde ölçülecek, gerekirse sonra eklenecek.
 *
 * Sensör olayları ve gönderim ana iş parçacığında (Looper) çalışır; ayrıca
 * kilit gerekmez.
 */
class MotionProbe(private val context: Context) : SensorEventListener, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PatikaMotion"
        private const val CHANNEL = "patika/motion"
        private const val EVENTS = "patika/motion_events"
        private const val SAMPLING_US = 20_000 // ~50 Hz
        private const val BATCH_MS = 200L
    }

    private val sensorManager: SensorManager? =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager?
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val buffer = ArrayList<Double>(64)

    private val flush = object : Runnable {
        override fun run() {
            send()
            if (sink != null) handler.postDelayed(this, BATCH_MS)
        }
    }

    private fun accelerometer(): Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(accelerometer() != null)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val sensor = accelerometer()
        if (sensor == null) {
            events.error("no_sensor", "İvmeölçer yok", null)
            return
        }
        sink = events
        val ok = sensorManager?.registerListener(this, sensor, SAMPLING_US, handler) == true
        if (!ok) {
            Log.w(TAG, "Sensör dinleyicisi kaydedilemedi")
            sink = null
            events.error("register_failed", "Sensör açılamadı", null)
            return
        }
        handler.postDelayed(flush, BATCH_MS)
    }

    override fun onCancel(arguments: Any?) = stop()

    private fun stop() {
        sensorManager?.unregisterListener(this)
        handler.removeCallbacks(flush)
        sink = null
        buffer.clear()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (sink == null) return
        buffer.add((event.timestamp / 1_000_000L).toDouble())
        buffer.add(event.values[0].toDouble())
        buffer.add(event.values[1].toDouble())
        buffer.add(event.values[2].toDouble())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun send() {
        val s = sink ?: return
        if (buffer.isEmpty()) return
        val batch = buffer.toDoubleArray()
        buffer.clear()
        s.success(batch)
    }
}
