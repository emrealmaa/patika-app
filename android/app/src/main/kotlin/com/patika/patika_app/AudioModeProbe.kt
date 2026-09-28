package com.patika.patika_app

import android.content.Context
import android.media.AudioManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Sistemin ses modunu verir (kanal `patika/audiomode`). SOS, kendi başlattığı
 * arama sürerken konuşmasın diye aramanın bitişini bununla izler:
 * `AudioManager.getMode()` izin gerektirmez; MODE_IN_CALL (2) telefon araması,
 * MODE_IN_COMMUNICATION (3) VoIP sürüyor demektir. Değer okunamazsa Dart
 * tarafı "bilinmiyor" sayar ve hiç konuşmaz.
 */
class AudioModeProbe(private val context: Context) {

    companion object {
        private const val CHANNEL = "patika/audiomode"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mode" -> {
                    val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    if (audio == null) result.success(null) else result.success(audio.mode)
                }
                else -> result.notImplemented()
            }
        }
    }
}
