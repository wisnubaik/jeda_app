package com.wishnotregret.berijeda

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class JedaForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "jeda_foreground_channel"
        const val NOTIF_ID = 1001
        const val ACTION_STOP = "com.wishnotregret.berijeda.STOP_SERVICE"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIF_ID, buildNotification())
        // START_STICKY: jika service dikill sistem karena resource rendah,
        // Android akan mencoba restart service ini kembali.
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Jeda - Pemantauan Aktif",
                NotificationManager.IMPORTANCE_MIN // ikon kecil, tidak mengganggu
            ).apply {
                description = "Notifikasi menunjukkan Jeda sedang memantau penggunaan smartphone"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): android.app.Notification {
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        openAppIntent?.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Jeda aktif memantau")
            .setContentText("Mendeteksi pola penggunaan smartphonemu hari ini")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openPendingIntent)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}