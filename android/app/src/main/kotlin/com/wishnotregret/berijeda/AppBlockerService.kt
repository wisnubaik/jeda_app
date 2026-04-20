package com.wishnotregret.berijeda

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.util.Log

class AppBlockerService : AccessibilityService() {

    companion object {
        var isBlockingActive = false // Trigger dari Flutter
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isBlockingActive) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return

            // Daftar aplikasi yang TIDAK diblokir (Sistem, Jeda sendiri, dll)
            val allowedApps = listOf(
                "com.wishnotregret.berijeda", 
                "com.android.systemui", 
                "com.transsion.XOSLauncher" // Launcher Infinix
            )

            if (!allowedApps.contains(packageName)) {
                Log.d("JedaBlocker", "Mendeteksi $packageName dibuka! MEMBLOKIR...")
                
                // Panggil paksa aplikasi Jeda ke depan!
                val launchIntent = packageManager.getLaunchIntentForPackage("com.wishnotregret.berijeda")
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    startActivity(launchIntent)
                }
            }
        }
    }

    override fun onInterrupt() {}
}