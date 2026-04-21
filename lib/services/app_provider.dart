import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import '../models/usage_data.dart';
import '../models/naive_bayes_model.dart';

class AppProvider extends ChangeNotifier {
  UsageData _data = UsageData();
  NaiveBayesModel? _model;
  int _prediction = 0;
  double _addictionProb = 0;
  bool _isLoading = false;
  bool _hasPermission = false;
  bool _isMonitoringEnabled = true;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  UsageData get data => _data;
  int get prediction => _prediction;
  double get addictionProb => _addictionProb;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get isMonitoringEnabled => _isMonitoringEnabled;
  String get status => _prediction == 0 ? 'AMAN' : 'BAHAYA';

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // Init notifikasi
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    // ✅ FIX: Bungkus dengan try-catch agar tidak crash jika asset belum ada
    try {
      _model = await NaiveBayesModel.getInstance();
      debugPrint("✅ Model Naive Bayes berhasil dimuat");
    } catch (e) {
      _model = null;
      debugPrint("⚠️ Model gagal dimuat, pakai fallback: $e");
    }

    // ✅ FIX: Cek permission dengan aman
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (e) {
      _hasPermission = false;
      debugPrint("⚠️ Gagal cek permission UsageStats: $e");
    }

    if (_hasPermission) await fetchUsageData();

    _listenOverlayEvents();

    _isLoading = false;
    notifyListeners();
  }

  void _listenOverlayEvents() {
    FlutterOverlayWindow.overlayListener.listen((event) async {
      if (event == null) return;
      final data = event as Map?;
      if (data == null) return;

      final action = data['action'] as String?;
      if (action == 'snooze') {
        final seconds = (data['seconds'] as num?)?.toInt() ?? 60;
        await applySnoozeNative(seconds);
      } else if (action == 'disable_monitoring') {
        await setMonitoring(false);
      }
    });
  }

  Future<void> setMonitoring(bool value) async {
    _isMonitoringEnabled = value;
    notifyListeners();
    if (!value) {
      await _syncBlockerToNative(false);
      try {
        final isActive = await FlutterOverlayWindow.isActive();
        if (isActive) await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
    } else {
      if (_prediction == 1) await _syncBlockerToNative(true);
    }
  }

  Future<void> _syncBlockerToNative(bool status) async {
    try {
      await platform.invokeMethod('setBlockingStatus', {'status': status});
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

  Future<bool> isOverlayPermissionGranted() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    await FlutterOverlayWindow.requestPermission();
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
      await _notificationsPlugin.show(
        999,
        '⚠️ SAATNYA JEDA!',
        'Segera istirahat!',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint("❌ Notif Gagal: $e");
    }
  }

  Future<void> showOverlayAlert() async {
    if (!_isMonitoringEnabled) return;
    try {
      final isGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!isGranted) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }
      final isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) {
        await FlutterOverlayWindow.showOverlay(
          enableDrag: false,
          overlayTitle: 'SAATNYA JEDA!',
          overlayContent: 'Penggunaanmu sudah berlebihan.',
          flag: OverlayFlag.defaultFlag,
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.auto,
          height: 500,
          width: WindowSize.matchParent,
        );
      }
    } catch (e) {
      debugPrint("❌ Overlay gagal: $e");
    }
  }

  Future<void> applySnoozeNative(int seconds) async {
    try {
      await platform.invokeMethod('setSnooze', {'seconds': seconds});
      try {
        final isActive = await FlutterOverlayWindow.isActive();
        if (isActive) await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
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

  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (e) {
      _hasPermission = false;
    }
    if (_hasPermission) await fetchUsageData();
    notifyListeners();
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (e) {
      _hasPermission = false;
    }
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

    _runPrediction();
    notifyListeners();
  }

  void _runPrediction() {
    if (_model != null) {
      final featureMap = _data.toFeatureMap();
      _prediction = _model!.predict(featureMap);
      _addictionProb = _model!.getAddictionProbability(featureMap);
      debugPrint(
        "🤖 Naive Bayes: prediction=$_prediction, prob=${(_addictionProb * 100).toStringAsFixed(1)}%",
      );
    } else {
      _prediction = _data.dailyScreenTime > 5.0 ? 1 : 0;
      _addictionProb = _prediction == 1 ? 0.88 : 0.15;
      debugPrint("⚠️ Model belum siap, pakai fallback threshold");
    }

    if (_prediction == 1 && _isMonitoringEnabled) {
      Future.delayed(
        const Duration(seconds: 1),
        () => _syncBlockerToNative(true),
      );
    } else {
      _syncBlockerToNative(false);
    }
  }

  Future<void> fetchUsageData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final endDate = DateTime.now();
      final startDate = DateTime(endDate.year, endDate.month, endDate.day);

      // ✅ FIX: Tangkap null / list kosong dengan aman
      List<UsageInfo> usageList = [];
      try {
        usageList = await UsageStats.queryUsageStats(startDate, endDate) ?? [];
      } catch (e) {
        debugPrint("⚠️ queryUsageStats error: $e");
        usageList = [];
      }

      // ✅ FIX: Jika list kosong, set data default dan keluar lebih awal
      if (usageList.isEmpty) {
        debugPrint(
          "⚠️ UsageStats kosong (mungkin belum ada izin atau hari baru)",
        );
        _data = UsageData(
          dailyScreenTime: 0,
          appSessions: 0,
          socialMediaUsage: 0,
          gamingTime: 0,
          notifications: _data.notifications,
          nightUsage: 0,
          appsInstalled: 0,
        );
        _runPrediction();
        _isLoading = false;
        notifyListeners();
        return;
      }

      double totalHours = 0.0;
      int totalSessions = 0;
      double socialMediaHours = 0.0;
      double gamingHours = 0.0;

      const socialPackages = {
        'com.instagram.android',
        'com.zhiliaoapp.musically',
        'com.facebook.katana',
        'com.twitter.android',
        'com.snapchat.android',
        'com.whatsapp',
        'com.tencent.mm',
      };

      const gamePackages = {
        'com.garena.game.codm',
        'com.mobile.legends',
        'com.pubg.imobile',
        'com.dts.freefireth',
        'com.supercell.clashofclans',
        'com.mojang.minecraftpe',
      };

      for (var info in usageList) {
        // ✅ FIX: Skip entry yang packageName-nya null
        final pkg = info.packageName;
        if (pkg == null || pkg.isEmpty) continue;

        // ✅ FIX: Parsing aman, skip jika null/kosong
        final rawTime = info.totalTimeInForeground;
        if (rawTime == null || rawTime.isEmpty) continue;
        final timeMs = double.tryParse(rawTime) ?? 0;
        if (timeMs <= 0) continue;

        final hours = timeMs / 1000 / 60 / 60;

        totalHours += hours;
        totalSessions += 1;

        if (socialPackages.contains(pkg)) socialMediaHours += hours;
        if (gamePackages.contains(pkg)) gamingHours += hours;
      }

      _data = UsageData(
        dailyScreenTime: totalHours,
        appSessions: totalSessions,
        socialMediaUsage: socialMediaHours,
        gamingTime: gamingHours,
        notifications: _data.notifications,
        nightUsage: 0.0,
        appsInstalled: usageList.length,
      );

      debugPrint(
        "📊 UsageStats: ${totalHours.toStringAsFixed(2)}j, $totalSessions sesi, "
        "sosmed=${socialMediaHours.toStringAsFixed(2)}j, game=${gamingHours.toStringAsFixed(2)}j",
      );

      _runPrediction();
    } catch (e) {
      debugPrint("❌ Gagal menarik data UsageStats: $e");
    }

    _isLoading = false;
    notifyListeners();
  }
}
