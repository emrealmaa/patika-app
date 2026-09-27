package com.patika.patika_app

import android.app.Notification
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Gelen mesaj bildirimlerini (varsayılan SMS uygulaması + WhatsApp) yakalayıp
 * Dart'a iletir (bkz. lib/platform/incoming_messages.dart). Gelen arama
 * kimliği bu servise DAHİL DEĞİL - CLAUDE.md'deki karar 1 arayan kimliğini
 * de buradan almayı öngörüyor ama o, gerçek telefon durumu PatikaCallService'e
 * bağlanınca ayrı bir adımda ele alınacak.
 *
 * Hangi bildirimler işlenir:
 * - Varsayılan SMS uygulaması (Telephony.Sms.getDefaultSmsPackage ile ÇALIŞMA
 *   ZAMANINDA sorgulanır - kullanıcı farklı bir uygulama seçmiş olabilir).
 * - WhatsApp (kişisel + iş).
 * Başka hiçbir uygulamadan bildirim okunmaz/iletilmez.
 *
 * Ne çıkarılır: önce MessagingStyle (son mesajın göndereni + metni - WhatsApp
 * ve çoğu modern SMS uygulaması bunu kullanır), yoksa başlık/metin. Grup
 * sohbetlerinde gönderen adı bazen doğru ayrıştırılamayabilir (bilinen sınır,
 * ilk sürümde mükemmelleştirilmedi).
 *
 * Tekrar ayıklama: özet bildirimleri (FLAG_GROUP_SUMMARY) tamamen atlanır;
 * her bildirim anahtarı için son (gönderen, metin) çifti bellekte tutulur,
 * aynısı tekrar gelirse (sessiz güncelleme) yeniden duyurulmaz.
 */
class PatikaNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PatikaNotifListener"
        private const val CHANNEL = "patika/notifications"
        private val WHATSAPP_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")
    }

    private val lastSeen = mutableMapOf<String, Pair<String, String>>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "Bildirim dinleyici bağlandı")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.i(TAG, "Bildirim dinleyici koptu")
        lastSeen.clear()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        try {
            handle(sbn)
        } catch (e: Exception) {
            Log.w(TAG, "Bildirim işlenemedi", e)
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        if (!isTracked(sbn.packageName)) return
        val notification = sbn.notification
        // Özet bildirimi: aynı sohbetin son mesajı zaten ayrı bir bildirimle
        // geldi, ikinci kez duyurmaya gerek yok.
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extracted = extract(notification) ?: return
        val (sender, body) = extracted
        if (sender.isBlank() || body.isBlank()) return

        val key = "${sbn.packageName}|${sbn.tag}|${sbn.id}"
        if (lastSeen[key] == sender to body) return
        lastSeen[key] = sender to body

        send(sender, body, sbn.packageName)
    }

    private fun isTracked(packageName: String): Boolean {
        if (packageName in WHATSAPP_PACKAGES) return true
        val defaultSms = try {
            Telephony.Sms.getDefaultSmsPackage(this)
        } catch (e: Exception) {
            null
        }
        return packageName == defaultSms
    }

    /** (gönderen, mesaj metni) - önce MessagingStyle'ın son mesajı, yoksa başlık/metin. */
    private fun extract(notification: Notification): Pair<String, String>? {
        val messagingStyle = NotificationCompat.MessagingStyle
            .extractMessagingStyleFromNotification(notification)
        val lastMessage = messagingStyle?.messages?.lastOrNull()
        if (lastMessage != null) {
            val sender = lastMessage.person?.name?.toString()
                ?: messagingStyle.conversationTitle?.toString()
                ?: return null
            val text = lastMessage.text?.toString() ?: return null
            return sender to text
        }

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return null
        val text = (
            extras.getCharSequence(Notification.EXTRA_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            )?.toString() ?: return null
        return title to text
    }

    private fun send(sender: String, body: String, packageName: String) {
        val engine = FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID) ?: return
        if (!engine.dartExecutor.isExecutingDart) return
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
            "message",
            mapOf("senderName" to sender, "body" to body, "appPackage" to packageName),
        )
    }
}
