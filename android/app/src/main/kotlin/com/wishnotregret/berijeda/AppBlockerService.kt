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
            val pkg = event.packageName?.toString()
            if (!pkg.isNullOrEmpty()) {
                // Abaikan keyboard/input method dan aplikasi Jeda sendiri.
                // Saat overlay tampil, Jeda menjadi foreground sesaat sehingga
                // currentPackage akan "flip" ke com.wishnotregret.berijeda —
                // ini membuat overlay dianggap sudah tidak di app terlarang
                // dan tidak muncul lagi setelah snooze. Dengan mengabaikannya,
                // currentPackage tetap menunjuk aplikasi asli (mis. Instagram).
                if (pkg.contains("inputmethod") ||
                    pkg.contains("latin") ||
                    pkg.contains("keyboard") ||
                    pkg == "com.wishnotregret.berijeda"
                ) {
                    return
                }
                currentPackage = pkg
            }
        }
    }

    private fun checkAndBlock() {
        val prefs = applicationContext.getSharedPreferences(
            "JedaPrefs", Context.MODE_PRIVATE
        )
        val isBlockingActiveMain = prefs.getBoolean("isBlockingActive", false)

        val flutterPrefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val isBlockingActiveBg = flutterPrefs.getBoolean("flutter.isBlockingActive_bg", false)

        // Cek PALING AWAL: matikan monitoring dari overlay
        val overlayDisableNow =
            flutterPrefs.getBoolean("flutter.overlay_disableMonitoring", false)
        if (overlayDisableNow) {
            prefs.edit().putBoolean("isBlockingActive", false).apply()
            flutterPrefs.edit()
                .putBoolean("flutter.overlay_disableMonitoring", false)
                .putBoolean("flutter.isBlockingActive_bg", false)
                .putBoolean("flutter.monitoring_disabled_today", true)
                .apply()
            overlayShownAt = 0L
            Log.d("JedaBlocker", "🛑 Monitoring dimatikan dari overlay")
            return
        }

        if (flutterPrefs.getBoolean("flutter.monitoring_disabled_today", false)) {
            Log.d("JedaBlocker", "⏹️ SKIP: monitoring_disabled_today = true")
            return
        }

        val isBlockingActive = isBlockingActiveMain || isBlockingActiveBg
        if (!isBlockingActive) {
            Log.d("JedaBlocker", "⏹️ SKIP: isBlockingActive = false (main=$isBlockingActiveMain, bg=$isBlockingActiveBg)")
            return
        }

        // Snooze dari overlay — dua flag boolean (short=10 detik, long=10 menit)
        val snoozeShort =
            flutterPrefs.getBoolean("flutter.overlay_snoozeShort", false)
        val snoozeLong =
            flutterPrefs.getBoolean("flutter.overlay_snoozeLong", false)
        if (snoozeShort || snoozeLong) {
            val secs = if (snoozeLong) 600L else 10L
            val until = System.currentTimeMillis() + (secs * 1000L)
            prefs.edit().putLong("snoozeUntil", until).apply()
            flutterPrefs.edit()
                .putBoolean("flutter.overlay_snoozeShort", false)
                .putBoolean("flutter.overlay_snoozeLong", false)
                .apply()
            overlayShownAt = 0L
            Log.d("JedaBlocker", "😴 Snooze dari overlay: $secs detik")
            return
        }

        val snoozeUntil = prefs.getLong("snoozeUntil", 0L)
        if (System.currentTimeMillis() < snoozeUntil) {
            Log.d("JedaBlocker", "⏹️ SKIP: masih snooze")
            return
        }

        // Jangan blokir app yang diperbolehkan
        if (allowedApps.contains(currentPackage)) {
            Log.d("JedaBlocker", "⏹️ SKIP: allowedApps ($currentPackage)")
            return
        }

        // Jangan blokir keyboard/input method atau launcher (universal semua HP)
        if (currentPackage.contains("inputmethod") ||
            currentPackage.contains("latin") ||
            currentPackage.contains("keyboard") ||
            currentPackage.contains("systemui") ||
            isLauncherPackage(currentPackage)
        ) {
            Log.d("JedaBlocker", "⏹️ SKIP: keyboard/launcher/system ($currentPackage)")
            return
        }

        // Cooldown agar tidak spam
        val now = System.currentTimeMillis()
        if (now - lastActionTime < ACTION_COOLDOWN_MS) {
            Log.d("JedaBlocker", "⏹️ SKIP: cooldown")
            return
        }
        lastActionTime = now

        Log.d("JedaBlocker", "🎯 Mendeteksi app terlarang: $currentPackage")

        // HANYA andalkan overlay. Jika izin overlay ada, tampilkan overlay dan
        // TIDAK PERNAH redirect. Redirect hanya fallback bila izin overlay
        // benar-benar tidak tersedia.
        if (Settings.canDrawOverlays(applicationContext)) {
            tryShowFlutterOverlay()
            Log.d("JedaBlocker", "📤 Minta Dart tampilkan overlay (flag-based v2)")
        } else {
            Log.w("JedaBlocker", "⚠️ Izin overlay tidak ada — fallback redirect")
            val launchIntent = packageManager
                .getLaunchIntentForPackage("com.wishnotregret.berijeda")
            launchIntent?.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            launchIntent?.let { startActivity(it) }
        }
    }

    private val launcherCache = mutableSetOf<String>()
    private fun isLauncherPackage(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        if (launcherCache.contains(pkg)) return true
        return try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val resolveInfos = packageManager.queryIntentActivities(homeIntent, 0)
            val homePackages = resolveInfos.map { it.activityInfo.packageName }.toSet()
            launcherCache.addAll(homePackages)
            homePackages.contains(pkg)
        } catch (e: Exception) {
            pkg.contains("launcher") || pkg.contains("home")
        }
    }
    // Menandai waktu terakhir overlay ditampilkan agar tidak spawn ulang
    // tiap siklus deteksi (mencegah "hilang lalu muncul lagi").
    private var overlayShownAt = 0L
    private val OVERLAY_REFRESH_MS = 60_000L

    private fun tryShowFlutterOverlay(): Boolean {
        if (!Settings.canDrawOverlays(applicationContext)) {
            Log.w("JedaBlocker", "Izin overlay belum diberikan")
            return false
        }
        // Jika overlay baru saja ditampilkan dan belum kedaluwarsa, jangan
        // spawn lagi (mencegah flicker).
        val now = System.currentTimeMillis()
        if (now - overlayShownAt < OVERLAY_REFRESH_MS) {
            return true
        }
        return try {
            // Tulis flag agar Dart menampilkan overlay lewat API resmi
            // (showOverlay). Reflection startService me-reuse isolate lama
            // sehingga initState + alarm tidak jalan.
            val fp = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            fp.edit().putBoolean("flutter.request_show_overlay", true).commit()
            overlayShownAt = now
            true
        } catch (e: Exception) {
            Log.e("JedaBlocker", "Gagal set flag overlay: ${e.message}")
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