package com.wishnotregret.berijeda

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "jeda_app/usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> {
                        result.success(isUsagePermissionGranted())
                    }
                    "requestPermission" -> {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    }
                    "getTodayStats" -> {
                        if (!isUsagePermissionGranted()) {
                            result.error("PERMISSION_DENIED", "Permission not granted", null)
                            return@setMethodCallHandler
                        }
                        result.success(getTodayStats())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isUsagePermissionGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getTodayStats(): Map<String, Any> {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startTime, endTime
        )

        val socialPackages = listOf(
            "instagram", "twitter", "facebook", "tiktok",
            "snapchat", "whatsapp", "telegram", "linkedin",
            "pinterest", "reddit", "youtube"
        )

        val gamingPackages = listOf(
            "supercell", "king", "mojang", "garena",
            "mobilelegends", "tencent", "roblox", "pubg"
        )

        var totalScreenTime = 0.0
        var appSessions = 0
        var socialMediaTime = 0.0
        var gamingTime = 0.0
        var appsInstalled = 0

        for (stat in stats) {
            val timeMs = stat.totalTimeInForeground
            if (timeMs <= 0) continue

            val timeHours = timeMs / 1000.0 / 3600.0
            totalScreenTime += timeHours
            appSessions++
            appsInstalled++

            val pkg = stat.packageName.lowercase()
            if (socialPackages.any { pkg.contains(it) }) {
                socialMediaTime += timeHours
            }
            if (gamingPackages.any { pkg.contains(it) }) {
                gamingTime += timeHours
            }
        }

        // Night usage (jam 22.00 sampai sekarang)
        var nightUsage = 0.0
        val now = Calendar.getInstance()
        if (now.get(Calendar.HOUR_OF_DAY) >= 22) {
            val nightCalendar = Calendar.getInstance()
            nightCalendar.set(Calendar.HOUR_OF_DAY, 22)
            nightCalendar.set(Calendar.MINUTE, 0)
            nightCalendar.set(Calendar.SECOND, 0)
            val nightStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                nightCalendar.timeInMillis,
                endTime
            )
            for (stat in nightStats) {
                if (stat.totalTimeInForeground > 0) {
                    nightUsage += stat.totalTimeInForeground / 1000.0 / 3600.0
                }
            }
        }

        return mapOf(
            "daily_screen_time" to totalScreenTime,
            "app_sessions" to appSessions.toDouble(),
            "social_media_usage" to socialMediaTime,
            "gaming_time" to gamingTime,
            "notifications" to 0.0,
            "night_usage" to nightUsage,
            "apps_installed" to appsInstalled.toDouble()
        )
    }
}