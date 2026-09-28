package com.patika.patika_app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Uygulamanın paket adı ve çalışan imzasının SHA-1 parmak izi (kanal
 * `patika/identity`).
 *
 * Neden: Google Cloud'da Routes/Places anahtarı "Android uygulaması"
 * kısıtlamasıyla (paket adı + SHA-1) sınırlandığında, REST çağrısı yapan
 * istemci bu iki değeri `X-Android-Package` ve `X-Android-Cert` başlıklarıyla
 * KENDİSİ göndermelidir; yoksa istek 403 alır. Değerler çalışan imzadan
 * okunur, yani debug, `direct` ve Play imzası her derlemede doğru gelir.
 * Parmak izi gizli değildir ama günlüğe de yazılmaz.
 */
class AppIdentity(private val context: Context) {

    companion object {
        private const val TAG = "PatikaAppIdentity"
        private const val CHANNEL = "patika/identity"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(
                    mapOf(
                        "package" to context.packageName,
                        "sha1" to certSha1(),
                    )
                )
                else -> result.notImplemented()
            }
        }
    }

    /** SHA-1, iki nokta üst üste yok, büyük harf; okunamazsa null. */
    private fun certSha1(): String? {
        return try {
            val signature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES,
                )
                val signing = info.signingInfo ?: return null
                // Birden çok imzacı varsa (nadir) ilkini alıyoruz; geçmiş
                // anahtarlar değil, şu an geçerli olanlar.
                signing.apkContentsSigners.firstOrNull()
            } else {
                @Suppress("DEPRECATION")
                val info = context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNATURES,
                )
                @Suppress("DEPRECATION")
                info.signatures?.firstOrNull()
            } ?: return null
            MessageDigest.getInstance("SHA-1")
                .digest(signature.toByteArray())
                .joinToString("") { "%02X".format(it) }
        } catch (e: Exception) {
            Log.w(TAG, "İmza okunamadı", e)
            null
        }
    }
}
