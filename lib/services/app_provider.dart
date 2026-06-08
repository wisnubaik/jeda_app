import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isSoundEnabled = true;
  bool _initialized = false;
  bool _notifListenerActive = false;
  Timer? _midnightTimer;
  Timer? _pollingTimer;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  final Map<String, DateTime> _lastNotifTime = {};
  static const Duration _notifCooldown = Duration(milliseconds: 500);

  UsageData get data => _data;
  int get prediction => _prediction;
  double get addictionProb => _addictionProb;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get isMonitoringEnabled => _isMonitoringEnabled;
  bool get isSoundEnabled => _isSoundEnabled;
  String get status => _prediction == 0 ? 'AMAN' : 'BAHAYA';

  Future<int> _countMissedNotifications(DateTime startOfDay) async {
  try {
    final now = DateTime.now();
    final allEvents = ((await UsageStats.queryEvents(startOfDay, now)) ?? [])
        .cast<EventUsageInfo>()
        .toList();

    const ignoredPkgs = {
      'android',
      'com.android.systemui',
      'com.android.phone',
      'com.wishnotregret.berijeda',
  'com.google.android.networkstack',     // ← tambah
  'com.google.android.packageinstaller', // ← sudah ada di systemPackagePrefixes tapi tambah aja lah bismillah
  'com.transsion.phonemaster',           // ← tambah
    };

    // ← TAMBAH: hitung per package untuk debug
    final Map<String, int> countPerPkg = {};
    int count = 0;

    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      if (et != 12) continue;
      final pkg = e.packageName ?? '';
      if (pkg.isEmpty || ignoredPkgs.contains(pkg)) continue;
      count++;
      countPerPkg[pkg] = (countPerPkg[pkg] ?? 0) + 1;
    }

    // ← TAMBAH: print per package
    countPerPkg.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..forEach((e) => debugPrint(
          '  📬 ${e.value}x │ ${e.key}'));

    debugPrint('📬 Notif dari queryEvents (catch-up): $count');
    return count;
  } catch (e) {
    debugPrint('❌ countMissedNotifications: $e');
    return 0;
  }
}

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _isLoading = true;
    notifyListeners();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    try {
      _model = await NaiveBayesModel.getInstance();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastDate = prefs.getString('last_date');
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);

    _isSoundEnabled = prefs.getBool('sound_enabled') ?? true;

    if (lastDate == todayStr) {
  final savedCount = prefs.getInt('notif_count') ?? 0;
  final eventCount = await _countMissedNotifications(startOfDay);
  _data.notifications = savedCount > eventCount ? savedCount : eventCount;
  await prefs.setInt('notif_count', _data.notifications);
  debugPrint('📊 Notif restore: saved=$savedCount, events=$eventCount, pakai=${_data.notifications}');
} else {
  _data.notifications = await _countMissedNotifications(startOfDay);
  await prefs.setString('last_date', todayStr);
  await prefs.setInt('notif_count', _data.notifications);
  debugPrint('🔄 Reset harian: notifikasi → ${_data.notifications}');
}

    await _initNotificationListener(prefs);

    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }

    if (_hasPermission) await fetchUsageData();

    _listenOverlayEvents();
    _scheduleMidnightReset();
    _startUsagePolling();
    platform.setMethodCallHandler((call) async {
    if (call.method == 'onAppResumed') {
      await onAppResumed();
    }
  });
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _initNotificationListener(SharedPreferences prefs) async {
    try {
      bool isGranted = await NotificationListenerService.isPermissionGranted();
      if (!isGranted) {
        await NotificationListenerService.requestPermission();
        isGranted = await NotificationListenerService.isPermissionGranted();
      }

      if (!isGranted) {
        debugPrint('⚠️ Izin notifikasi tidak diberikan');
        return;
      }

      NotificationListenerService.notificationsStream.listen((event) async {
        final pkg = event.packageName ?? '';

        const ignored = {
  'android',
  'com.android.systemui',
  'com.android.phone',       // telepon masuk — tetap filter
  'com.wishnotregret.berijeda',
};
        if (pkg.isEmpty || ignored.contains(pkg)) return;
        final hasRemoved = event.hasRemoved ?? false;
        if (hasRemoved) return;

        final nowTime = DateTime.now();
        final lastTime = _lastNotifTime[pkg];
        if (lastTime != null &&
            nowTime.difference(lastTime) < _notifCooldown) {
          debugPrint('🔕 Dedup notif: $pkg (cooldown)');
          return;
        }
        _lastNotifTime[pkg] = nowTime;

        _data.notifications += 1;
        await prefs.setInt('notif_count', _data.notifications);
        debugPrint('🔔 Notif [+1]: $pkg | Total: ${_data.notifications}');
        _runPrediction();
        notifyListeners();
      });

      debugPrint('✅ Notification listener aktif');
    } catch (e) {
      debugPrint('❌ Gagal init notif listener: $e');
    }
  }

  Future<void> toggleSound(bool value) async {
    _isSoundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', value);
    notifyListeners();
  }

  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    final duration = nextMidnight.difference(now);

    debugPrint('⏰ Reset dijadwalkan dalam: '
        '${duration.inHours}j ${duration.inMinutes % 60}m');

    _midnightTimer = Timer(duration, () async {
      debugPrint('🔄 RESET TENGAH MALAM');
      final prefs = await SharedPreferences.getInstance();
      final now2 = DateTime.now();
      final todayStr = '${now2.year}-${now2.month}-${now2.day}';
      _lastNotifTime.clear();

      _data = UsageData(
        dailyScreenTime: 0,
        appSessions: 0,
        socialMediaUsage: 0,
        gamingTime: 0,
        notifications: 0,
        nightUsage: 0,
        appsInstalled: 0,
      );
      await prefs.setString('last_date', todayStr);
      await prefs.setInt('notif_count', 0);

      _runPrediction();
      notifyListeners();
      _scheduleMidnightReset();
      _startUsagePolling();
    });
  }

  void _startUsagePolling() {
  _pollingTimer?.cancel();
  _pollingTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
    if (_hasPermission) {
      await fetchUsageData();
      debugPrint('🔁 Auto-refresh usage data');
    }
  });
  debugPrint('✅ Polling timer aktif (interval: 5 menit)');
}

  Future<void> fetchUsageData() async {
  _isLoading = true;
  notifyListeners();

  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final startOfDayMs = startOfDay.millisecondsSinceEpoch;
    final nowMs = now.millisecondsSinceEpoch;

    const socialPackages = {
      'com.instagram.android',
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.ss.android.ugc.aweme',
      'com.facebook.katana',
      'com.twitter.android',
      'com.snapchat.android',
      'com.whatsapp',
      'com.whatsapp.w4b',
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

    // App transsion yang BOLEH dihitung (dipakai user secara sadar)
const transsionUserApps = {
  'com.transsion.soundrecorder',  // Perekam — user pakai manual
  'com.transsion.deskclock',      // Jam — user pakai manual  
  'com.transsion.camera',         // Kamera
  'com.transsion.contacts',       // Kontak
  'com.transsion.filemanager',    // File manager
  'com.transsion.calendar',       // Kalender
};

const systemPackagePrefixes = [
  'com.android.',
  'com.google.android.inputmethod',
  'com.google.android.gms',
  'com.google.android.gsf',
  'com.google.android.packageinstaller',
];

const systemExactPackages = {
  'android',
  'com.android.systemui',
  // com.wishnotregret.berijeda → TETAP JANGAN difilter (sudah benar)
  'com.google.android.launcher',
  'com.infinix.launcher',
  'com.transsion.hilauncher',
  'com.transsion.XOSLauncher',    // ← launcher utama Infinix
  'com.android.launcher',
  'com.android.launcher3',
  'com.google.android.apps.wellbeing',
  'com.google.android.permissioncontroller',
  'com.google.android.captiveportallogin',
  'com.google.android.tts',                    // TTS service
  'com.google.android.googlequicksearchbox',   // Search bar
  'com.community.oneroom',
};

// App yang DIKECUALIKAN dari filter com.android.* prefix
// karena ini app user yang nyata
const androidPrefixExceptions = {
  'com.android.chrome',       // Google Chrome
  'com.android.settings',    // Pengaturan sistem (user buka manual)
  'com.android.vending',     // Play Store
  'com.android.camera',      // Kamera AOSP
  'com.android.dialer',      // Telepon
  'com.android.contacts',    // Kontak AOSP
  'com.android.calculator',  // Kalkulator
  'com.android.calendar',    // Kalender AOSP
};

bool isSystemPackage(String pkg) {
  // Whitelist: app transsion yang dipakai user
  if (transsionUserApps.contains(pkg)) return false;
  
  // Whitelist: pengecualian dari prefix com.android.*
  if (androidPrefixExceptions.contains(pkg)) return false;

  // Exact match
  if (systemExactPackages.contains(pkg)) return true;

  // Prefix match
  for (final prefix in systemPackagePrefixes) {
    if (pkg.startsWith(prefix)) return true;
  }
  return false;
}

    final allEvents =
        ((await UsageStats.queryEvents(startOfDay, now)) ?? [])
            .cast<EventUsageInfo>()
            .toList();

    // ════ STEP 1: Kumpulkan timestamp screen-off (event type 2 dari 'android') ════
    // Screen-off events dipakai untuk memotong sesi yang masih "terbuka"
    final List<int> screenOffTimestamps = [];
    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      final pkg = e.packageName ?? '';
      // Event type 2 dari package 'android' = screen off / keyguard
      if (pkg == 'android' && (et == 2 || et == 15)) {
        final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
        if (tsMs >= startOfDayMs) screenOffTimestamps.add(tsMs);
      }
    }

    // ════ STEP 2: Hitung screen time via events MURNI type 1 & 2 saja ════
    // TIDAK pakai event 23 (ACTIVITY_RESUMED) untuk menghindari double-counting
    final Map<String, int> foregroundStart = {};
    final Map<String, double> eventsDuration = {};
    final Set<String> appsWithBackground = {};

    // Pass pertama: catat semua app yang pernah punya BACKGROUND event
    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      final pkg = e.packageName ?? '';
      if (et == 2 && pkg.isNotEmpty && !isSystemPackage(pkg)) {
        appsWithBackground.add(pkg);
      }
    }

    // Pass kedua: hitung durasi
    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      final pkg = e.packageName ?? '';
      if (pkg.isEmpty || isSystemPackage(pkg)) continue;

      // HANYA event 1 (FOREGROUND) dan 2 (BACKGROUND) — buang event 23
      if (et != 1 && et != 2) continue;

      final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
      if (tsMs < startOfDayMs) continue;

      if (et == 1) {
        // Jika sudah ada foreground sebelumnya untuk app ini tanpa background,
        // itu phantom — reset saja
        foregroundStart[pkg] = tsMs;
      } else if (et == 2) {
        final startMs = foregroundStart[pkg];
        if (startMs != null) {
          final clampedStart = startMs < startOfDayMs ? startOfDayMs : startMs;
          final duration = tsMs - clampedStart;
          if (duration > 0 && duration <= 7200000) { // max 2 jam per sesi
            eventsDuration[pkg] = (eventsDuration[pkg] ?? 0) + duration;
          }
          foregroundStart.remove(pkg);
        }
      }
    }

    // ════ STEP 3: Sesi yang masih aktif (belum ada BACKGROUND) ════
    // Hanya hitung jika:
    // (a) App pernah punya background event sebelumnya (bukan phantom)
    // (b) Durasi dari foreground hingga sekarang ≤ 30 menit
    // (c) Tidak ada screen-off setelah foreground dimulai
    foregroundStart.forEach((pkg, startMs) {
      if (startMs < startOfDayMs) return;
      if (!appsWithBackground.contains(pkg)) return;

      // Cek apakah ada screen-off setelah sesi dimulai
      final hasScreenOffAfterStart = screenOffTimestamps.any((t) => t > startMs);
      if (hasScreenOffAfterStart) return; // Layar sudah mati, sesi tidak valid

      final duration = nowMs - startMs;
      // Batasi sesi aktif maksimal 30 menit (DW lebih konservatif)
      if (duration > 0 && duration <= 1800000) {
        eventsDuration[pkg] = (eventsDuration[pkg] ?? 0) + duration.toDouble();
      }
    });

    // ════ STEP 4: Cross-check dengan queryUsageStats ════
    // queryUsageStats memberikan angka agregat per app — mirip yang DW pakai
    double queryStatsTotalMs = 0;
    double queryStatsSocialMs = 0;
    double queryStatsGamingMs = 0;
    int appCount = 0;
    final Map<String, double> queryStatsPerApp = {};

    try {
      final usageStatsList = await UsageStats.queryUsageStats(startOfDay, now);
      if (usageStatsList != null) {
        for (final stat in usageStatsList) {
          final pkg = stat.packageName ?? '';
          if (pkg.isEmpty || isSystemPackage(pkg)) continue;
          final totalTime = int.tryParse(
                  stat.totalTimeInForeground?.toString() ?? '0') ?? 0;
          if (totalTime > 0) {
            queryStatsTotalMs += totalTime;
            appCount++;
            if (socialPackages.contains(pkg)) queryStatsSocialMs += totalTime;
            if (gamePackages.contains(pkg)) queryStatsGamingMs += totalTime;
            queryStatsPerApp[pkg] = totalTime.toDouble();
            debugPrint('  📊 queryStats: ${(totalTime/3600000).toStringAsFixed(2)}j │ $pkg');
          }
        }
      }

      debugPrint('📊 queryStats TOTAL RAW: ${queryStatsTotalMs}ms');
debugPrint('📊 Jumlah app terhitung: ${appCount}');

    } catch (e) {
      debugPrint('⚠️ queryUsageStats error: $e');
    }

    // Hitung total dari event-based
    double totalScreenMs = 0;
    double socialMs = 0;
    double gamingMs = 0;

    eventsDuration.forEach((pkg, ms) {
      totalScreenMs += ms;
      if (socialPackages.contains(pkg)) socialMs += ms;
      if (gamePackages.contains(pkg)) gamingMs += ms;
      debugPrint('  📱 ${(ms/3600000).toStringAsFixed(2)}j │ $pkg');
    });

    // ════ STEP 5: Rekonsiliasi — event-based sebagai utama ════
double reconciledTotal = 0;
double reconciledSocial = 0;
double reconciledGaming = 0;

final allPkgs = {...eventsDuration.keys, ...queryStatsPerApp.keys};

for (final pkg in allPkgs) {
  final eventVal = eventsDuration[pkg] ?? 0.0;
  final queryVal = queryStatsPerApp[pkg] ?? 0.0;
  double chosen;

  if (eventVal > 0) {
    // Ada event-based → pakai event-based (bebas dari phantom kemarin)
    chosen = eventVal;
  } else {
    // Tidak ada event → pakai queryStats tapi batasi 30 menit
    chosen = queryVal > 1800000 ? 1800000.0 : queryVal;
  }

  reconciledTotal += chosen;
  if (socialPackages.contains(pkg)) reconciledSocial += chosen;
  if (gamePackages.contains(pkg)) reconciledGaming += chosen;
}

totalScreenMs = reconciledTotal;
socialMs = reconciledSocial;
gamingMs = reconciledGaming;
debugPrint('⚖️ Rekonsiliasi: ${(totalScreenMs/3600000).toStringAsFixed(2)}j');
    // ════ SCREEN UNLOCKS ════
    int sessionCount = 0;
    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      final pkg = e.packageName ?? '';
      if (pkg != 'android') continue;
      if (et != 18) continue;
      sessionCount++;
    }
    debugPrint('🔓 Screen unlocks: $sessionCount');

    // ════ NIGHT USAGE ════
    double nightScreenMs = 0.0;
    final nightStart1 = DateTime(now.year, now.month, now.day - 1, 22, 0, 0);
    final nightEnd1 = DateTime(now.year, now.month, now.day, 5, 0, 0);
    final nightStart2 = DateTime(now.year, now.month, now.day, 22, 0, 0);
    final Map<String, int?> foregroundTimestamp = {};

    for (final e in allEvents) {
      final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
      final pkg = e.packageName ?? '';
      if (pkg.isEmpty || isSystemPackage(pkg)) continue;
      if (et != 1 && et != 2) continue;

      final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
      final eventTime = DateTime.fromMillisecondsSinceEpoch(tsMs);

      if (et == 1) {
        foregroundTimestamp[pkg] = tsMs;
      } else if (et == 2) {
        final startMs = foregroundTimestamp[pkg];
        if (startMs != null) {
          nightScreenMs += _intersectWithNight(
            DateTime.fromMillisecondsSinceEpoch(startMs),
            eventTime,
            nightStart1,
            nightEnd1,
            nightStart2,
            now,
          );
          foregroundTimestamp.remove(pkg);
        }
      }
    }

    foregroundTimestamp.forEach((pkg, startMs) {
      if (startMs == null) return;
      nightScreenMs += _intersectWithNight(
        DateTime.fromMillisecondsSinceEpoch(startMs),
        now,
        nightStart1,
        nightEnd1,
        nightStart2,
        now,
      );
    });

    final screenHours = totalScreenMs / 3600000.0;
    final socialHours = socialMs / 3600000.0;
    final gamingHours = gamingMs / 3600000.0;
    final nightUsageHours = nightScreenMs / 3600000.0;

    debugPrint('════════════════════════════════════');
    debugPrint('📊 RINGKASAN USAGE DATA');
    debugPrint('   Screen Time  : ${screenHours.toStringAsFixed(2)}j');
    debugPrint('   queryStats   : ${(queryStatsTotalMs/3600000).toStringAsFixed(2)}j');
    debugPrint('   Sessions     : $sessionCount');
    debugPrint('   Night Usage  : ${nightUsageHours.toStringAsFixed(2)}j');
    debugPrint('   Social       : ${socialHours.toStringAsFixed(2)}j');
    debugPrint('   Notif        : ${_data.notifications}');
    debugPrint('════════════════════════════════════');

    _data = UsageData(
      dailyScreenTime: screenHours,
      appSessions: sessionCount,
      socialMediaUsage: socialHours,
      gamingTime: gamingHours,
      notifications: _data.notifications,
      nightUsage: nightUsageHours,
      appsInstalled: 0,
    );

    _runPrediction();
  } catch (e, st) {
    debugPrint('❌ fetchUsageData error: $e\n$st');
  }

  _isLoading = false;
  notifyListeners();
}

  double _intersectWithNight(
    DateTime sStart,
    DateTime sEnd,
    DateTime n1Start,
    DateTime n1End,
    DateTime n2Start,
    DateTime now,
  ) {
    double total = 0;

    final i1Start = sStart.isAfter(n1Start) ? sStart : n1Start;
    final i1End = sEnd.isBefore(n1End) ? sEnd : n1End;
    if (i1Start.isBefore(i1End)) {
      total += i1End.difference(i1Start).inMilliseconds;
    }

    if (now.isAfter(n2Start)) {
      final i2Start = sStart.isAfter(n2Start) ? sStart : n2Start;
      final i2End = sEnd.isBefore(now) ? sEnd : now;
      if (i2Start.isBefore(i2End)) {
        total += i2End.difference(i2Start).inMilliseconds;
      }
    }

    return total;
  }

  Future<void> openUsageSettings() async {
  // Panggil native supaya flag _waitingForPermission di-set dulu
  try {
    await platform.invokeMethod('openUsageSettings');
  } catch (_) {
    await UsageStats.grantUsagePermission();
  }
}

  Future<void> openAccessibilitySettings() async {
    await platform.invokeMethod('openAccessibilitySettings');
  }

  Future<void> openNotificationSettings() async {
  // Buka settings manual, hindari bug double-reply di v0.3.5
  try {
    await platform.invokeMethod('openNotificationSettings');
  } catch (_) {}
}

  Future<void> onAppResumed() async {
  debugPrint('🔄 App resumed — re-cek permission');

  if (!_notifListenerActive) {
    final prefs = await SharedPreferences.getInstance();
    await _initNotificationListener(prefs);
  }

  try {
    _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
  } catch (_) {
    _hasPermission = false;
  }

  debugPrint('🔑 hasPermission setelah resume: $_hasPermission'); // ← sudah ada
  debugPrint('🔑 initialized: $_initialized'); // ← tambah ini
  
  if (_hasPermission) {
    try {
      await fetchUsageData();
    } catch (e) {
      debugPrint('❌ fetchUsageData di resume gagal: $e');
    }
  }

  notifyListeners();
  debugPrint('🔔 notifyListeners dipanggil'); // ← tambah ini
}

  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }
    if (_hasPermission) await fetchUsageData();
    notifyListeners();
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }
    notifyListeners();
  }

  void _listenOverlayEvents() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) async {
        if (event == null) return;
        final data = event as Map?;
        if (data == null) return;
        final action = data['action'] as String?;
        if (action == 'snooze') {
          await applySnoozeNative((data['seconds'] as num?)?.toInt() ?? 60);
        } else if (action == 'disable_monitoring') {
          await setMonitoring(false);
        }
      });
    } catch (e) {
      debugPrint('❌ Overlay listener: $e');
    }
  }

  Future<void> setMonitoring(bool value) async {
    _isMonitoringEnabled = value;
    notifyListeners();
    if (!value) {
      await _syncBlockerToNative(false);
      await _notificationsPlugin.cancel(999);
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
    } else {
      if (_prediction == 1) await _syncBlockerToNative(true);
    }
  }

  Future<void> _syncBlockerToNative(bool status) async {
    try {
      await platform.invokeMethod('setBlockingStatus', {'status': status});
    } on PlatformException catch (e) {
      debugPrint('❌ Sync native: ${e.message}');
    }
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await platform.invokeMethod('checkAccessibilityEnabled');
    } catch (_) {
      return false;
    }
  }

  Future<void> requestAccessibilityPermission() => openAccessibilitySettings();

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

  Future<void> applySnoozeNative(int seconds) async {
    try {
      await platform.invokeMethod('setSnooze', {'seconds': seconds});
      await _notificationsPlugin.cancel(999);
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
    } on PlatformException catch (e) {
      debugPrint('❌ Snooze: ${e.message}');
    }
  }

  Future<void> enforceBlockIfNecessary() async {
    try {
      await platform.invokeMethod('enforceBlockIfNecessary');
    } catch (e) {
      debugPrint('❌ enforceBlock: $e');
    }
  }

  Future<void> showNotificationAlert() async {
    if (!_isMonitoringEnabled) return;
    try {
      await _notificationsPlugin.show(
        999,
        '⚠️ SAATNYA JEDA!',
        'Segera istirahat!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'jeda_alarm_v3',
            'Alarm Jeda Keras',
            importance: Importance.max,
            priority: Priority.high,
            playSound: _isSoundEnabled,
            sound: _isSoundEnabled
                ? const RawResourceAndroidNotificationSound('alarm')
                : null,
            enableVibration: _isSoundEnabled,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Notif alert: $e');
    }
  }

  Future<void> showOverlayAlert() async {
    if (!_isMonitoringEnabled) return;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }
      if (!await FlutterOverlayWindow.isActive()) {
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
      debugPrint('❌ Overlay: $e');
    }
  }

  Future<void> resetDailyData() async {
    _data = UsageData();
    _prediction = 0;
    _addictionProb = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_count', 0);
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
    debugPrint('🧠 INPUT MODEL:');
    debugPrint('   screen_time : ${_data.dailyScreenTime.toStringAsFixed(2)}j');
    debugPrint('   unlocks     : ${_data.appSessions}x');
    debugPrint('   notif       : ${_data.notifications}x');

    final result = _model!.predict([
      _data.dailyScreenTime,           // features[0]: screen_time (jam)
      _data.appSessions.toDouble(),    // features[1]: unlocks (kali)
      _data.notifications.toDouble(), // features[2]: notif (kali)
    ]);
    _prediction = result['prediction'];
    _addictionProb = result['probability'];
    
    debugPrint('🧠 Prediksi: $_prediction | Prob: $_addictionProb');
    debugPrint('   Input: screen=${_data.dailyScreenTime.toStringAsFixed(2)}j'
        ' | unlocks=${_data.appSessions}'
        ' | notif=${_data.notifications}');
  } else {
    // Fallback jika model gagal load
    _prediction = _data.dailyScreenTime > 5.0 ? 1 : 0;
    _addictionProb = _prediction == 1 ? 0.88 : 0.15;
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
}