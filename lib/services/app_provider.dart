import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/usage_data.dart';
import '../models/naive_bayes_model.dart';
import '../services/usage_stats_service.dart';

class AppProvider extends ChangeNotifier {
  UsageData _data = UsageData();
  NaiveBayesModel? _model;
  int _prediction = 0;
  double _addictionProb = 0;
  bool _isLoading = false;
  bool _hasPermission = false;
  bool _isMonitoringEnabled = true;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  UsageData get data => _data;
  int get prediction => _prediction;
  double get addictionProb => _addictionProb;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get isMonitoringEnabled => _isMonitoringEnabled;
  String get status => _prediction == 0 ? 'AMAN' : 'BAHAYA';

  // --- FITUR BARU: NATIVE BLOCKER & SAKLAR ---
  Future<void> setMonitoring(bool value) async {
    _isMonitoringEnabled = value;
    notifyListeners();
    if (!value) {
      await _syncBlockerToNative(false);
    } else {
      if (_prediction == 1) await _syncBlockerToNative(true);
    }
  }

  Future<void> _syncBlockerToNative(bool status) async {
    try {
      await platform.invokeMethod('setBlockingStatus', {'status': status});
      debugPrint("📡 Sync Native Blocker: $status");
    } on PlatformException catch (e) {
      debugPrint("❌ Gagal sync native: ${e.message}");
    }
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await platform.invokeMethod('checkAccessibilityEnabled');
    } catch (_) {
      return false;
    }
  }

  Future<void> requestAccessibilityPermission() async {
    await platform.invokeMethod('openAccessibilitySettings');
  }

  Future<void> showNotificationAlert() async {
    if (!_isMonitoringEnabled) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'jeda_suara_final_v1',
        'Alarm Jeda Keras',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      await _notificationsPlugin.show(999, '⚠️ SAATNYA JEDA!', 'Segera istirahat!', const NotificationDetails(android: androidDetails));
    } catch (e) {
      debugPrint("❌ Notif Gagal: $e");
    }
  }

  // --- FUNGSI KIRIM SNOOZE DETIK KE KOTLIN ---
  Future<void> applySnoozeNative(int seconds) async {
    try {
      await platform.invokeMethod('setSnooze', {'seconds': seconds});
      debugPrint("⏱️ Native Snooze Aktif: $seconds detik");
    } on PlatformException catch (e) {
      debugPrint("❌ Gagal Snooze Native: ${e.message}");
    }
  }

  Future<void> enforceBlockIfNecessary() async {
    try {
      await platform.invokeMethod('enforceBlockIfNecessary');
    } catch (e) {
      debugPrint("❌ Gagal enforce native: $e");
    }
  }

  // --- KEMBALIKAN FUNGSI LAMA YANG SEMPAT TERHAPUS ---
  Future<void> requestPermission() async {
    await UsageStatsService.requestPermission();
    _hasPermission = await UsageStatsService.isPermissionGranted();
    if (_hasPermission) {
      await fetchUsageData();
    }
    notifyListeners();
  }

  Future<void> checkPermission() async {
    _hasPermission = await UsageStatsService.isPermissionGranted();
    notifyListeners();
  }

  Future<void> resetDailyData() async {
    _data = UsageData();
    _prediction = 0;
    _addictionProb = 0;
    notifyListeners();
  }

  void updateData({
    double? screenTime,
    int? appSessions,
    double? socialMedia,
    double? gaming,
    int? notifications,
    double? nightUsage,
    int? appsInstalled,
  }) {
    if (screenTime != null) _data.dailyScreenTime = screenTime;
    if (appSessions != null) _data.appSessions = appSessions;
    if (socialMedia != null) _data.socialMediaUsage = socialMedia;
    if (gaming != null) _data.gamingTime = gaming;
    if (notifications != null) _data.notifications = notifications;
    if (nightUsage != null) _data.nightUsage = nightUsage;
    if (appsInstalled != null) _data.appsInstalled = appsInstalled;
    
    if (_data.dailyScreenTime > 5.0) {
      _prediction = 1;
      _addictionProb = 0.88;
      if (_isMonitoringEnabled) {
        Future.delayed(const Duration(seconds: 2), () {
          _syncBlockerToNative(true);
        });
      }
    } else {
      _prediction = 0;
      _addictionProb = 0.15;
      _syncBlockerToNative(false);
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    _model = await NaiveBayesModel.getInstance();
    _hasPermission = await UsageStatsService.isPermissionGranted();
    await fetchUsageData();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchUsageData() async {
    _isLoading = true;
    notifyListeners();

    _data = UsageData(
      dailyScreenTime: 7.5,
      appSessions: 85,
      socialMediaUsage: 4.5,
      gamingTime: 3.0,
      notifications: 150,
      nightUsage: 2.5,
      appsInstalled: 42,
    );

    if (_data.dailyScreenTime > 5.0) {
      _prediction = 1;
      _addictionProb = 0.88;
      
      if (_isMonitoringEnabled) {
        Future.delayed(const Duration(seconds: 2), () {
          _syncBlockerToNative(true);
        });
      }
    } else {
      _prediction = 0;
      _addictionProb = 0.15;
      _syncBlockerToNative(false);
    }

    _isLoading = false;
    notifyListeners();
  }
}