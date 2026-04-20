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
            UsageStatsManager.INTERVAL_BEST, startTime, endTime
        )

        val systemPackages = listOf(
            "android", "com.android", "com.google.android",
            "com.samsung", "com.miui", "com.xiaomi",
            "com.huawei", "com.oppo", "com.vivo",
            "com.wishnotregret.berijeda"
        )

        var totalScreenTime = 0.0
        var appSessions = 0
        var socialMediaTime = 0.0
        var gamingTime = 0.0
        val pm = packageManager
        val appList = mutableListOf<Map<String, Any>>()

        for (stat in stats) {
            val timeMs = stat.totalTimeInForeground
            if (timeMs <= 0) continue

            val pkg = stat.packageName.lowercase()
            if (systemPackages.any { pkg.startsWith(it) }) continue
            if (stat.lastTimeUsed < startTime) continue

            val timeHours = timeMs / 1000.0 / 3600.0
            totalScreenTime += timeHours
            appSessions++

            var category = -1
            var appName = stat.packageName
            try {
                val appInfo = pm.getApplicationInfo(stat.packageName, 0)
                category = appInfo.category
                appName = pm.getApplicationLabel(appInfo).toString()
                android.util.Log.d("JEDA", "App: $appName | category: $category")
            } catch (e: Exception) { }

            val isSocial = category == android.content.pm.ApplicationInfo.CATEGORY_SOCIAL
            val isGame = category == android.content.pm.ApplicationInfo.CATEGORY_GAME

            if (isSocial) socialMediaTime += timeHours
            if (isGame) gamingTime += timeHours

            appList.add(mapOf(
                "name" to appName,
                "package" to stat.packageName,
                "duration" to timeHours,
                "category" to category
            ))
        }

        // Night usage jam 21.00 - 00.00
        var nightUsage = 0.0
        val nowHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (nowHour >= 21) {
            val nightCalendar = Calendar.getInstance()
            nightCalendar.set(Calendar.HOUR_OF_DAY, 21)
            nightCalendar.set(Calendar.MINUTE, 0)
            nightCalendar.set(Calendar.SECOND, 0)
            nightCalendar.set(Calendar.MILLISECOND, 0)

            val nightStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                nightCalendar.timeInMillis,
                endTime
            )
            for (stat in nightStats) {
                val pkg = stat.packageName.lowercase()
                if (systemPackages.any { pkg.startsWith(it) }) continue
                if (stat.totalTimeInForeground > 0) {
                    nightUsage += stat.totalTimeInForeground / 1000.0 / 3600.0
                }
            }
        }

        // Apps installed (hanya app yang bisa dibuka user)
        val installedApps = pm.getInstalledApplications(0)
        val userApps = installedApps.filter { appInfo ->
            pm.getLaunchIntentForPackage(appInfo.packageName) != null &&
            appInfo.packageName != packageName
        }.size

        return mapOf(
            "daily_screen_time" to totalScreenTime,
            "app_sessions" to appSessions.toDouble(),
            "social_media_usage" to socialMediaTime,
            "gaming_time" to gamingTime,
            "notifications" to 0.0,
            "night_usage" to nightUsage,
            "apps_installed" to userApps.toDouble(),
            "app_list" to appList
        )
    }
}