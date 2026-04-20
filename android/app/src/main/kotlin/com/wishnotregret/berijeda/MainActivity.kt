package com.wishnotregret.berijeda

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings
import android.content.Context
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.wishnotregret.berijeda/blocker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBlockingStatus" -> {
                    val status = call.argument<Boolean>("status") ?: false
                    val prefs = applicationContext.getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("isBlockingActive", status).apply()
                    result.success(null)
                }
                "setSnooze" -> {
                    val secondsStr = call.argument<Any>("seconds").toString()
                    val seconds = secondsStr.toLongOrNull() ?: 0L
                    val snoozeUntil = System.currentTimeMillis() + (seconds * 1000L)
                    val prefs = applicationContext.getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putLong("snoozeUntil", snoozeUntil).apply()
                    Log.d("JedaBlocker", "Snooze aktif selama $seconds detik")
                    result.success(null)
                }
                // 💡 INI KODE BARU: Cek sebelum melempar ke layar
                "enforceBlockIfNecessary" -> {
                    val prefs = applicationContext.getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                    val isBlockingActive = prefs.getBoolean("isBlockingActive", false)

                    if (isBlockingActive && !AppBlockerService.allowedApps.contains(AppBlockerService.currentPackage)) {
                        val launchIntent = packageManager.getLaunchIntentForPackage("com.wishnotregret.berijeda")
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            startActivity(launchIntent)
                        }
                    }
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "checkAccessibilityEnabled" -> {
                    val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                    val isEnabled = enabledServices?.contains(packageName) == true
                    result.success(isEnabled)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}