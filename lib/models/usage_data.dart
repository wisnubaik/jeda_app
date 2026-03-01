class UsageData {
  double dailyScreenTime;
  int appSessions;
  double socialMediaUsage;
  double gamingTime;
  int notifications;
  double nightUsage;
  int appsInstalled;

  UsageData({
    this.dailyScreenTime = 0,
    this.appSessions = 0,
    this.socialMediaUsage = 0,
    this.gamingTime = 0,
    this.notifications = 0,
    this.nightUsage = 0,
    this.appsInstalled = 0,
  });

  Map<String, double> toFeatureMap() {
    return {
      'daily_screen_time': dailyScreenTime,
      'app_sessions': appSessions.toDouble(),
      'social_media_usage': socialMediaUsage,
      'gaming_time': gamingTime,
      'notifications': notifications.toDouble(),
      'night_usage': nightUsage,
      'apps_installed': appsInstalled.toDouble(),
    };
  }
}