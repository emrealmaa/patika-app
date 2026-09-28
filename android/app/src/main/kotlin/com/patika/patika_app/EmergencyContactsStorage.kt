package com.patika.patika_app

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Acil kişi listesini (Faz 7) saklar. Kanal `patika/emergency_contacts`.
 *
 * [Context.getNoBackupFilesDir] BİLEREK kullanılıyor: Android bu dizini
 * otomatik yedeğe (bulut yedeği ve cihazdan cihaza aktarım) HİÇ almaz -
 * ayrı bir yedek kuralı (XML) ya da ek paket gerekmeden, platformun kendi
 * garantisi. Uygulamanın diğer verileri (ayarlar, takma adlar) olağan
 * SharedPreferences'ta kalıp yedeklenmeye devam ediyor; yalnızca acil kişi
 * listesi bu istisna.
 *
 * Dosya küçük (en fazla birkaç kişi) olduğu için tek parça JSON metni
 * olarak okunup yazılıyor - ayrıştırma Dart tarafında.
 */
class EmergencyContactsStorage(private val context: Context) {

    companion object {
        private const val TAG = "PatikaEmergencyContacts"
        private const val CHANNEL = "patika/emergency_contacts"
        private const val FILE_NAME = "emergency_contacts.json"
    }

    private val file: File
        get() = File(context.noBackupFilesDir, FILE_NAME)

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    try {
                        result.success(if (file.exists()) file.readText(Charsets.UTF_8) else null)
                    } catch (e: Exception) {
                        Log.w(TAG, "Okunamadı", e)
                        result.success(null)
                    }
                }
                "write" -> {
                    try {
                        val json = call.argument<String>("json") ?: "[]"
                        file.writeText(json, Charsets.UTF_8)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.w(TAG, "Yazılamadı", e)
                        result.error("write_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
