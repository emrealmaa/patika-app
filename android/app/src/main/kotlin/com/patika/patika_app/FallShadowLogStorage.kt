package com.patika.patika_app

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Düşme algılamanın gölge kaydını (Faz 7c) saklar. Kanal `patika/fall_log`.
 *
 * [EmergencyContactsStorage] ile aynı gerekçe: [Context.getNoBackupFilesDir]
 * otomatik yedeğe ve cihazdan cihaza aktarıma hiç girmez. Kayıtta konum ve
 * ham sensör verisi yok (yalnızca zaman + özet değerler + sonuç), ama yine de
 * kişinin günlük hareketine dair bir iz; buluta gitmesi gerekmez.
 *
 * Dosya en fazla 200 kayıt (birkaç on KB); tek parça JSON metni olarak okunup
 * yazılıyor, ayrıştırma ve budama Dart tarafında. Yazma geçici dosyaya yapılıp
 * yeniden adlandırılır: yazarken süreç ölürse eski kayıt bozulmadan kalır.
 */
class FallShadowLogStorage(private val context: Context) {

    companion object {
        private const val TAG = "PatikaFallLog"
        private const val CHANNEL = "patika/fall_log"
        private const val FILE_NAME = "fall_shadow_log.json"
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
                        val tmp = File(context.noBackupFilesDir, "$FILE_NAME.tmp")
                        tmp.writeText(json, Charsets.UTF_8)
                        if (!tmp.renameTo(file)) {
                            // Bazı dosya sistemlerinde hedef varken renameTo başarısız olur.
                            file.delete()
                            if (!tmp.renameTo(file)) throw IllegalStateException("rename")
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.w(TAG, "Yazılamadı", e)
                        result.error("write_failed", e.message, null)
                    }
                }
                "clear" -> {
                    try {
                        file.delete()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.w(TAG, "Silinemedi", e)
                        result.error("clear_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
