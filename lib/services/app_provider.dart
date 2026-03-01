import 'package:flutter/foundation.dart';
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

  UsageData get data => _data;
  int get prediction => _prediction;
  double get addictionProb => _addictionProb;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String get status => _prediction == 0 ? 'AMAN' : 'BAHAYA';

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _model = await NaiveBayesModel.getInstance();
    _hasPermission = await UsageStatsService.isPermissionGranted();

    if (_hasPermission) {
      await fetchUsageData();
    }

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

    final stats = await UsageStatsService.getTodayStats();

    _data = UsageData(
      dailyScreenTime: stats['daily_screen_time'] ?? 0,
      appSessions: (stats['app_sessions'] ?? 0).toInt(),
      socialMediaUsage: stats['social_media_usage'] ?? 0,
      gamingTime: stats['gaming_time'] ?? 0,
      notifications: 0,
      nightUsage: stats['night_usage'] ?? 0,
      appsInstalled: (stats['apps_installed'] ?? 0).toInt(),
    );

    await runPrediction();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> runPrediction() async {
    if (_model == null) return;
    final features = _data.toFeatureMap();
    _prediction = _model!.predict(features);
    _addictionProb = _model!.getAddictionProbability(features);
    notifyListeners();
  }

  // Fallback: input manual
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
    notifyListeners();
  }
}