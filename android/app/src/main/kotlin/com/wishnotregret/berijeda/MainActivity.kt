package com.wishnotregret.berijeda

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result as FlutterResult

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.wishnotregret.berijeda/blocker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).setMethodCallHandler { call: MethodCall, result: FlutterResult ->
            when (call.method) {

                "setBlockingStatus" -> {
                    val status = call.argument<Boolean>("status") ?: false
                    getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                        .edit().putBoolean("isBlockingActive", status).apply()
                    Log.d("JedaMain", "Blocking status: $status")
                    result.success(null)
                }

                "setSnooze" -> {
                    val seconds =
                        call.argument<Any>("seconds").toString().toLongOrNull() ?: 0L
                    val snoozeUntil = System.currentTimeMillis() + (seconds * 1000L)
                    getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                        .edit().putLong("snoozeUntil", snoozeUntil).apply()
                    Log.d("JedaMain", "Snooze aktif: $seconds detik")
                    result.success(null)
                }

                "enforceBlockIfNecessary" -> {
                    val prefs =
                        getSharedPreferences("JedaPrefs", Context.MODE_PRIVATE)
                    val isBlocking = prefs.getBoolean("isBlockingActive", false)
                    val isSnoozing =
                        System.currentTimeMillis() < prefs.getLong("snoozeUntil", 0L)

                    if (isBlocking && !isSnoozing &&
                        !AppBlockerService.allowedApps.contains(AppBlockerService.currentPackage)
                    ) {
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                        intent?.addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        )
                        intent?.let { startActivity(it) }
                    }
                    result.success(null)
                }

                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }

                "checkAccessibilityEnabled" -> {
                    val enabled = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                    )?.contains(packageName) == true
                    result.success(enabled)
                }

                // ✅ BARU: Cek izin overlay
                "checkOverlayPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }

                // ✅ BARU: Minta izin overlay
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(this)
                    ) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        Log.d("JedaMain", "Membuka pengaturan izin overlay")
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}