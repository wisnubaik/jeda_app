package com.wishnotregret.berijeda

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AppBlockerService : AccessibilityService() {

    companion object {
        var currentPackage: String = "com.transsion.XOSLauncher"
        val allowedApps = listOf(
            "com.wishnotregret.berijeda",
            "com.android.systemui",
            "com.transsion.XOSLauncher",
            "com.android.launcher",
            "com.android.launcher3",
            "com.transsion.hilauncher",
            "com.android.settings",
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    // Cooldown 5 detik agar overlay tidak spam muncul
    private var lastActionTime = 0L
    private val ACTION_COOLDOWN_MS = 5000L

    private val checkRunnable = object : Runnable {
        override fun run() {
            checkAndBlock()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 100
        }
        serviceInfo = info
        handler.post(checkRunnable)
        Log.d("JedaBlocker", "AppBlockerService terhubung ✅")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (!event.packageName.isNullOrEmpty()) {
                currentPackage = event.packageName.toString()
            }
        }
    }

    private fun checkAndBlock() {
        val prefs = applicationContext.getSharedPreferences(
            "JedaPrefs", Context.MODE_PRIVATE
        )
        val isBlockingActive = prefs.getBoolean("isBlockingActive", false)
        if (!isBlockingActive) return

        // Cek snooze
        val snoozeUntil = prefs.getLong("snoozeUntil", 0L)
        if (System.currentTimeMillis() < snoozeUntil) return

        // Jangan blokir app yang diperbolehkan
        if (allowedApps.contains(currentPackage)) return

        // Cooldown agar tidak spam
        val now = System.currentTimeMillis()
        if (now - lastActionTime < ACTION_COOLDOWN_MS) return
        lastActionTime = now

        Log.d("JedaBlocker", "Mendeteksi app terlarang: $currentPackage")

        // ✅ FIX UTAMA: Tampilkan overlay Flutter di atas app yang sedang dibuka
        // TANPA redirect / keluar dari app
        if (tryShowFlutterOverlay()) {
            Log.d("JedaBlocker", "✅ Overlay berhasil ditampilkan")
        } else {
            // Fallback: buka Jeda jika overlay gagal (misal izin belum diberikan)
            Log.w("JedaBlocker", "⚠️ Overlay gagal, fallback ke launch app")
            val launchIntent = packageManager
                .getLaunchIntentForPackage("com.wishnotregret.berijeda")
            launchIntent?.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            launchIntent?.let { startActivity(it) }
        }
    }

    private fun tryShowFlutterOverlay(): Boolean {
        // Cek izin SYSTEM_ALERT_WINDOW
        if (!Settings.canDrawOverlays(applicationContext)) {
            Log.w("JedaBlocker", "Izin overlay belum diberikan")
            return false
        }
        return try {
            // Start overlay service dari plugin flutter_overlay_window
            val overlayClass = Class.forName(
    "flutter.overlay.window.flutter_overlay_window.OverlayService"
)
            val intent = Intent(applicationContext, overlayClass)
            applicationContext.startService(intent)
            true
        } catch (e: Exception) {
            Log.e("JedaBlocker", "Gagal start overlay service: ${e.message}")
            false
        }
    }

    override fun onInterrupt() {
        Log.w("JedaBlocker", "Service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(checkRunnable)
        Log.d("JedaBlocker", "AppBlockerService dihentikan")
    }
}