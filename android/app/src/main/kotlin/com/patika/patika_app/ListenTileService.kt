package com.patika.patika_app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Hızlı Ayarlar karosu "Patika: Konuş": dokununca uygulama "dinle"
 * talimatıyla öne gelir ve dinleme başlar (Dart tarafında
 * VoiceController.startListening(ListenSource.tile)).
 *
 * Uygulamayı öne getirmek bilinçli bir tercih: dinleme ön planda başlıyor,
 * böylece Android 14'ün arka planda mikrofon kısıtına takılmıyor.
 *
 * Telefon kilitliyse önce kilit açma isteniyor (unlockAndRun). Uygulamayı
 * kilit ekranının üstünde göstermek bilerek seçilmedi: rehber/arama gibi
 * işlevler kilitli telefonda açığa çıkardı.
 *
 * Bu servis Dart motorunu BAŞLATMAZ; süreç yalnızca karo için başlarsa
 * (panel açılınca) uygulama kendi kendine bağlanıp konuşmaya başlamaz
 * (bkz. MainActivity).
 */
class ListenTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = getString(R.string.tile_label)
            contentDescription = getString(R.string.tile_description)
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) {
            unlockAndRun { launchListen() }
        } else {
            launchListen()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun launchListen() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_LISTEN
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
