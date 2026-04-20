package com.wishnotregret.berijeda

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.content.Context
import android.util.Log
import android.os.Handler
import android.os.Looper

class AppBlockerService : AccessibilityService() {

    companion object {
        var currentPackage: String = "com.transsion.XOSLauncher"
        val allowedApps = listOf(
            "com.wishnotregret.berijeda", 
            "com.android.systemui", 
            "com.transsion.XOSLauncher",
            "com.android.settings"
        )
    }

    // 💡 STOPWATCH NATIVE: Berdetak setiap 1 detik untuk mengintai!
    private val handler = Handler(Looper.getMainLooper())
    private val checkRunnable = object : Runnable {
        override fun run() {
            checkAndBlock()
            handler.postDelayed(this, 1000) // Ulangi setiap 1000ms (1 detik)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        handler.post(checkRunnable) // Nyalakan stopwatch saat Aksesibilitas ON
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName != null) {
            currentPackage = event.packageName.toString()
        }
        checkAndBlock() // Cek juga setiap kali user nyentuh layar
    }

    private fun checkAndBlock() {
        val prefs = applicationContext.getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
        val isBlockingActive = prefs.getBoolean("isBlockingActive", false)
        if (!isBlockingActive) return

        val snoozeUntil = prefs.getLong("snoozeUntil", 0L)
        if (System.currentTimeMillis() < snoozeUntil) return 

        if (!AppBlockerService.allowedApps.contains(currentPackage)) {
            Log.d("JedaBlocker", "Waktu Habis! Menyeret $currentPackage...")
            
            val launchIntent = packageManager.getLaunchIntentForPackage("com.wishnotregret.berijeda")
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)
                
                // 💡 SINKRONISASI: Kita tidak perlu bikin kode notifikasi rumit di sini, 
                // Biarkan Activity Jeda yang muncul nanti yang memicu suaranya di Flutter.
            }
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(checkRunnable) // Matikan stopwatch kalau dimatikan
    }
}