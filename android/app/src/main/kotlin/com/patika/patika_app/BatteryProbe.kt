package com.patika.patika_app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Telefonun pil yüzdesini ve şarj durumunu verir (kanal `patika/battery`).
 *
 * `ACTION_BATTERY_CHANGED` "sticky" bir yayındır: alıcı vermeden
 * `registerReceiver(null, filtre)` son değeri döndürür, izin gerekmez ve
 * kalıcı bir alıcı kaydı yoktur. Dart tarafı bunu 30 sn'de bir yoklar
 * (bkz. `AppState.pollPhoneBattery`); olay tabanlı `BroadcastReceiver`,
 * Dart motorunun etkinlikten ayrıldığı yapıda ek ömür yönetimi gerektirirdi.
 *
 * Değer okunamazsa `null` döner; Dart tarafı bunu "bilinmiyor" sayar ve
 * uydurma bir değer söylemez.
 */
class BatteryProbe(private val context: Context) {

    companion object {
        private const val CHANNEL = "patika/battery"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(read())
                else -> result.notImplemented()
            }
        }
    }

    private fun read(): Map<String, Any>? {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return null
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return mapOf("level" to (level * 100 / scale), "charging" to charging)
    }
}
