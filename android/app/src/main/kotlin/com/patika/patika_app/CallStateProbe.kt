package com.patika.patika_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Telefonun arama durumu ve gelen aramayı aç/reddet (kanal `patika/call_state`).
 *
 * - Durum: `READ_PHONE_STATE` ile; Android 12+ (API 31) `TelephonyCallback`,
 *   eskilerde `PhoneStateListener`. Telefon numarası ALINMAZ (`READ_CALL_LOG`
 *   yok; Play'de kısıtlı ve gereksiz). Arayan adı ayrı yoldan,
 *   `PatikaNotificationListener`'ın yakaladığı arama bildiriminden gelir
 *   (Faz 4b karar 1).
 * - Aç/reddet: `ANSWER_PHONE_CALLS` ile `TelecomManager.acceptRingingCall`
 *   (API 26+) ve `endCall` (API 28+). İkisi de API 29'da "kullanımdan
 *   kalkmış" işaretli ama çalışıyor; yerine geçen API (`InCallService`)
 *   varsayılan arama uygulaması olmayı gerektirir.
 *
 * Durum değişimi Dart'a `onState` ("idle" | "ringing" | "offhook") ile gider.
 */
class CallStateProbe private constructor(private val context: Context) {

    companion object {
        private const val TAG = "PatikaCallState"
        const val CHANNEL = "patika/call_state"

        @Volatile
        private var instance: CallStateProbe? = null

        /** Süreç başına tek örnek: etkinlik yeniden oluşunca dinleyici ikinci kez kaydedilmesin. */
        fun get(context: Context): CallStateProbe =
            instance ?: synchronized(this) {
                instance ?: CallStateProbe(context.applicationContext).also { instance = it }
            }
    }

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var callback: Any? = null
    private var lastState: String = "idle"

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(start())
                    "answer" -> result.success(answer())
                    "reject" -> result.success(reject())
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun canAnswer() =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && granted(Manifest.permission.ANSWER_PHONE_CALLS)

    /** İzin varsa dinleyiciyi kaydeder (bir kez). */
    private fun start(): Map<String, Any> {
        if (!granted(Manifest.permission.READ_PHONE_STATE)) {
            return mapOf("active" to false, "canAnswer" to false, "state" to "idle")
        }
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        if (callback == null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) = emit(state)
                    }
                    tm.registerTelephonyCallback(ContextCompat.getMainExecutor(context), cb)
                    callback = cb
                } else {
                    @Suppress("DEPRECATION")
                    val listener = object : PhoneStateListener() {
                        @Deprecated("API 31 öncesi")
                        override fun onCallStateChanged(state: Int, phoneNumber: String?) = emit(state)
                    }
                    @Suppress("DEPRECATION")
                    tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                    callback = listener
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "Arama durumu dinlenemedi: izin")
                return mapOf("active" to false, "canAnswer" to false, "state" to "idle")
            }
        }
        return mapOf("active" to true, "canAnswer" to canAnswer(), "state" to lastState)
    }

    private fun emit(state: Int) {
        val name = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
            else -> "idle"
        }
        lastState = name
        main.post { channel?.invokeMethod("onState", name) }
    }

    @Suppress("DEPRECATION")
    private fun answer(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !granted(Manifest.permission.ANSWER_PHONE_CALLS)) {
            return false
        }
        return try {
            (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).acceptRingingCall()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Arama açılamadı: ${e.javaClass.simpleName}")
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun reject(): Boolean {
        if (!canAnswer()) return false
        return try {
            (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).endCall()
        } catch (e: Exception) {
            Log.w(TAG, "Arama reddedilemedi: ${e.javaClass.simpleName}")
            false
        }
    }
}
