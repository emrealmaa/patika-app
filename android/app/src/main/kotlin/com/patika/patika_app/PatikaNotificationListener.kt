package com.patika.patika_app

import android.service.notification.NotificationListenerService
import android.util.Log

/**
 * Gelen bildirimleri (arayan kimliği, mesaj içeriği - Faz 4b) okuyacak servis.
 * Şimdilik yalnızca iskelet: sistemin "Bildirim erişimi" listesinde görünüp
 * bağlanabilmek için var - `onNotificationPosted` henüz ekli değil, hiçbir
 * bildirim içeriği işlenmiyor/saklanmıyor. Sıradaki adım bunu doldurmak.
 */
class PatikaNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PatikaNotifListener"
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "Bildirim dinleyici bağlandı")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.i(TAG, "Bildirim dinleyici koptu")
    }
}
