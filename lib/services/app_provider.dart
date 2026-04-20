import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // WAJIB UNTUK JALUR NATIVE
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

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // ==========================================
  // JALUR KOMUNIKASI KE KOTLIN (NATIVE)
  // ==========================================
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  UsageData get data => _data;
  int get prediction => _prediction;
  double get addictionProb => _addictionProb;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String get status => _prediction == 0 ? 'AMAN' : 'BAHAYA';

  // ==========================================
  // FUNGSI 1: AKTIFKAN PEMBLOKIR (NATIVE)
  // ==========================================
  Future<void> activateBlocker() async {
    try {
      await platform.invokeMethod('setBlockingStatus', {'status': true});
      debugPrint("🔥 BLOKIR NATIVE AKTIF!");
    } on PlatformException catch (e) {
      debugPrint("❌ Gagal mengaktifkan blokir: ${e.message}");
    }
  }

  // ==========================================
  // FUNGSI 2: MINTA IZIN AKSESIBILITAS KE USER
  // ==========================================
  Future<void> requestAccessibilityPermission() async {
    try {
      await platform.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      debugPrint("❌ Gagal buka setting: ${e.message}");
    }
  }

  // ==========================================
  // FUNGSI 3: NOTIFIKASI SUARA PERINGATAN
  // ==========================================
  Future<void> showNotificationAlert() async {
    try {
      const AndroidInitializationSettings initSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: initSettingsAndroid);
      await _notificationsPlugin.initialize(initSettings);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'jeda_suara_final_v1', 
        'Alarm Jeda Keras',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true, 
      );

      const NotificationDetails platformSpecifics =
          NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        999,
        'SAATNYA JEDA! ⚠️',
        'Pola penggunaan berlebihan. Layar akan diblokir!',
        platformSpecifics,
      );
      debugPrint("🔔 NOTIFIKASI SUKSES TERPANGGIL!");
    } catch (e) {
      debugPrint("❌ NOTIFIKASI GAGAL: $e");
    }
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

  Future<void> requestPermission() async {
    await UsageStatsService.requestPermission();
    _hasPermission = await UsageStatsService.isPermissionGranted();
    if (_hasPermission) {
      await fetchUsageData();
    }
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

    // 💡 LOGIKA PREDIKSI & TRIGGER BLOKIR OTOMATIS
    if (_data.dailyScreenTime > 5.0) {
      _prediction = 1;
      _addictionProb = 0.88; 
      
      // TRIGGER OTOMATIS: Bunyikan notif dan nyalakan mesin blokir Native!
      Future.delayed(const Duration(seconds: 2), () {
        showNotificationAlert();
        activateBlocker();
      });
      
    } else {
      _prediction = 0;
      _addictionProb = 0.15; 
    }

    _isLoading = false;
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
      
      Future.delayed(const Duration(seconds: 2), () {
        showNotificationAlert();
        activateBlocker();
      });
      
    } else {
      _prediction = 0;
      _addictionProb = 0.15;
    }
    notifyListeners();
  }
}