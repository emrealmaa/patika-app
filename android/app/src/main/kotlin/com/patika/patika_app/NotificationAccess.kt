package com.patika.patika_app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bildirim dinleyici erişimi (Faz 4b, iskelet) - `NotificationListenerService`
 * henüz yazılmadı (`PatikaNotificationListener.kt`, sonraki adım). Bu yalnızca
 * durumu sorup ("Patika etkin bir dinleyici mi") ayar ekranını açıyor; normal
 * çalışma zamanı izni değil, kullanıcı sistem ayarlarından elle açıyor.
 */
class NotificationAccess(private val context: Context) {

    companion object {
        private const val CHANNEL = "patika/notifications"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(isEnabled())
                "openSettings" -> {
                    openSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isEnabled(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context)
            .contains(context.packageName)

    private fun openSettings() {
        context.startActivity(
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
