package com.patika.patika_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Pil optimizasyonu muafiyeti (kanal `patika/battery_optimization`).
 *
 * Ekran kapalıyken saatlerce çalışma (gözlük bağlantısı, navigasyon, SOS)
 * için uygulamanın Doze/uygulama bekletme kısıtlamasından muaf olması
 * gerekebilir.
 *
 * - `direct`: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (yalnızca
 *   `src/direct/AndroidManifest.xml`) ile doğrudan sistem penceresi
 *   (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
 * - `play`: bu izin Play politikasında yalnızca belirli uygulama türlerine
 *   açık; izin istenmez, liste ayar ekranı açılır
 *   (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`), kullanıcı elle seçer.
 *
 * Pencere/ayar sonucu geri dönmez: Dart `isIgnoring` ile yoklar.
 */
class BatteryOptimization(private val context: Context) {

    companion object {
        private const val TAG = "PatikaBatteryOpt"
        private const val CHANNEL = "patika/battery_optimization"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoring" -> result.success(isIgnoring())
                "request" -> result.success(open(BuildConfig.DIRECT_ACTIONS))
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoring(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** direct: sistem penceresi; play (ya da pencere açılamazsa): liste ekranı. */
    @SuppressLint("BatteryLife")
    private fun open(direct: Boolean): String {
        if (direct) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        .setData(Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                return "dialog"
            } catch (e: Exception) {
                Log.w(TAG, "Pencere açılamadı, ayar ekranına düşülüyor: ${e.javaClass.simpleName}")
            }
        }
        return try {
            context.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            "settings"
        } catch (e: Exception) {
            Log.w(TAG, "Ayar ekranı açılamadı: ${e.javaClass.simpleName}")
            "failed"
        }
    }
}
