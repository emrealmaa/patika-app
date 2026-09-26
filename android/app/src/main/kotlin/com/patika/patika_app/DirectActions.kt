package com.patika.patika_app

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Onaydan sonra doğrudan arama ve SMS - YALNIZCA "direct" derleme türünde
 * etkin (BuildConfig.DIRECT_ACTIONS; izinler src/direct/AndroidManifest.xml).
 * "play" türünde [available] false döner ve Dart eski akışa (arama/SMS
 * ekranını açma) düşer.
 *
 * Arama TelecomManager.placeCall ile yapılır, ACTION_CALL ile değil:
 * ACTION_CALL bir ekran (activity) başlatır ve Android 10+ arka plandaki
 * uygulamanın ekran başlatmasını engeller - ekran kilitliyken gözlükten
 * gelen "Ahmet'i ara" sessizce başarısız olurdu. placeCall ekran başlatmaz.
 *
 * SMS: uzun mesaj parçalara bölünür; TÜM parçalar operatöre ulaştı
 * bildirilmeden "gönderildi" denmez (görme engelli kullanıcı ekrana bakıp
 * kontrol edemez - duyurunun doğru olması kritik). 30 sn'de cevap yoksa
 * zaman aşımı.
 */
class DirectActions(private val context: Context) {

    companion object {
        private const val TAG = "PatikaDirectActions"
        private const val CHANNEL = "patika/direct"
        private const val SMS_SENT_ACTION = "com.patika.patika_app.SMS_SENT"
        private const val SMS_TIMEOUT_MS = 30_000L
    }

    private val main = Handler(Looper.getMainLooper())
    private var nextRequestId = 0

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(BuildConfig.DIRECT_ACTIONS)
                "call" -> result.success(placeCall(call.argument<String>("number") ?: ""))
                "sendSms" -> sendSms(
                    call.argument<String>("number") ?: "",
                    call.argument<String>("body") ?: "",
                ) { status -> result.success(status) }
                else -> result.notImplemented()
            }
        }
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun placeCall(number: String): Boolean {
        if (!BuildConfig.DIRECT_ACTIONS || number.isBlank()) return false
        if (!granted(Manifest.permission.CALL_PHONE)) return false
        return try {
            val telecom = context.getSystemService(TelecomManager::class.java)
            telecom.placeCall(Uri.fromParts("tel", number, null), Bundle())
            true
        } catch (e: Exception) {
            Log.w(TAG, "Arama başlatılamadı", e)
            false
        }
    }

    /** Sonuç: "sent", "failed:<kod>", "timeout", "unavailable". */
    private fun sendSms(number: String, body: String, done: (String) -> Unit) {
        if (!BuildConfig.DIRECT_ACTIONS || number.isBlank() || body.isBlank() ||
            !granted(Manifest.permission.SEND_SMS)
        ) {
            done("unavailable")
            return
        }

        val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        val parts = sms.divideMessage(body)
        val requestId = nextRequestId++
        val action = "$SMS_SENT_ACTION.$requestId"
        var remaining = parts.size
        var failure: Int? = null
        var finished = false

        lateinit var receiver: BroadcastReceiver
        fun finish(status: String) {
            if (finished) return
            finished = true
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            done(status)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (resultCode != Activity.RESULT_OK && failure == null) failure = resultCode
                remaining--
                if (remaining <= 0) finish(failure?.let { "failed:$it" } ?: "sent")
            }
        }
        ContextCompat.registerReceiver(
            context, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        val sentIntents = ArrayList<PendingIntent>()
        for (i in parts.indices) {
            val intent = Intent(action).setPackage(context.packageName)
            sentIntents.add(
                PendingIntent.getBroadcast(
                    context, requestId * 100 + i, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT,
                ),
            )
        }

        try {
            sms.sendMultipartTextMessage(number, null, parts, sentIntents, null)
        } catch (e: Exception) {
            Log.w(TAG, "SMS gönderilemedi", e)
            finish("failed:exception")
            return
        }
        main.postDelayed({ finish("timeout") }, SMS_TIMEOUT_MS)
    }
}
