import 'package:flutter/services.dart';

class UsageStatsService {
  static const _channel = MethodChannel('jeda_app/usage_stats');

  static Future<bool> isPermissionGranted() async {
    try {
      final bool result = await _channel.invokeMethod('isPermissionGranted');
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  static Future<Map<String, double>> getTodayStats() async {
    try {
      final Map result = await _channel.invokeMethod('getTodayStats');
      return {
        'daily_screen_time': (result['daily_screen_time'] ?? 0).toDouble(),
        'app_sessions': (result['app_sessions'] ?? 0).toDouble(),
        'social_media_usage': (result['social_media_usage'] ?? 0).toDouble(),
        'gaming_time': (result['gaming_time'] ?? 0).toDouble(),
        'notifications': (result['notifications'] ?? 0).toDouble(),
        'night_usage': (result['night_usage'] ?? 0).toDouble(),
        'apps_installed': (result['apps_installed'] ?? 0).toDouble(),
      };
    } catch (_) {
      return {
        'daily_screen_time': 0,
        'app_sessions': 0,
        'social_media_usage': 0,
        'gaming_time': 0,
        'notifications': 0,
        'night_usage': 0,
        'apps_installed': 0,
      };
    }
  }
}