package com.wishnotregret.berijeda

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Tandai bahwa perangkat baru saja reboot. Flag ini dibaca oleh
            // callbackDispatcher (Dart) agar notifikasi "sudah memperbarui
            // data" hanya muncul sekali setelah reboot, bukan tiap 15 menit.
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit().putBoolean("flutter.just_booted", true).apply()

            // Mulai Foreground Service — tampilkan notifikasi persisten
            // "Jeda aktif memantau" sebagai sinyal visual ke pengguna
            // bahwa sistem sudah aktif kembali pasca-restart.
            // WorkManager periodic task tidak perlu didaftarkan ulang
            // di sini karena AndroidX WorkManager menyimpan task di
            // database internal SQLite dan menjadwalkan ulang secara
            // otomatis setelah reboot tanpa intervensi tambahan.
            val serviceIntent = Intent(context, JedaForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }
}