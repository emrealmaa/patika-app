package com.patika.patika_app

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Düşme algılamanın AÇIK modu için kullanıcının bu cihazda verdiği onayı
 * (Faz 7c-2) saklar. Kanal `patika/fall_consent`.
 *
 * Onay, [Context.getNoBackupFilesDir] içindeki küçük bir dosyadır: otomatik
 * yedeğe ve cihazdan cihaza aktarıma hiç girmez ([FallShadowLogStorage] ve
 * [EmergencyContactsStorage] ile aynı gerekçe). Böylece ayarlar yedekten geri
 * yüklenip `on` gelse bile, yeni/başka cihazda bu dosya YOKTUR ve açık mod
 * silahlanmaz: onay o cihazda yeniden, iki adımlı olarak istenir. Uygulama
 * verisi silinince ya da kaldırılınca dosya da gider.
 *
 * Dosyanın yokluğu her zaman "onay yok" demektir; okuma hatası da aynı
 * (güvenli) yönde çözülür.
 */
class FallOpenConsentStorage(private val context: Context) {

    companion object {
        private const val TAG = "PatikaFallConsent"
        private const val CHANNEL = "patika/fall_consent"
        private const val FILE_NAME = "fall_open_consent"
    }

    private val file: File
        get() = File(context.noBackupFilesDir, FILE_NAME)

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "granted" -> {
                    try {
                        result.success(file.exists())
                    } catch (e: Exception) {
                        Log.w(TAG, "Okunamadı", e)
                        result.success(false)
                    }
                }
                "grant" -> {
                    try {
                        file.writeText("granted", Charsets.UTF_8)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Yazılamadı", e)
                        result.success(false)
                    }
                }
                "revoke" -> {
                    try {
                        file.delete()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.w(TAG, "Silinemedi", e)
                        result.error("revoke_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
