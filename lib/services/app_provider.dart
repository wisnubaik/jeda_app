import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../models/usage_data.dart';
import '../models/naive_bayes_model.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'package:google_fonts/google_fonts.dart';

// ══════════════════════════════════════════════════════════
// WORKMANAGER CALLBACK DISPATCHER
// Wajib top-level function (bukan method di dalam class),
// karena dijalankan di background isolate terpisah oleh
// WorkManager Android. Tugasnya: jalankan ulang fetchUsageData()
// + _runPrediction() yang SUDAH ADA, tanpa logic baru.
// ══════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    try {
      final provider = AppProvider();
      await provider._loadAppNames();

      // Muat notif_count yang sudah tersimpan dari sesi UI sebelumnya,
      // supaya instance AppProvider baru ini tidak mulai dari 0.
      try {
        final prefs = await SharedPreferences.getInstance();
        provider._data.notifications = prefs.getInt('notif_count') ?? 0;
      } catch (e) {
        debugPrint('❌ Gagal load notif_count di background: $e');
      }

      bool hasPermission = false;
      try {
        hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
      } catch (_) {}

      if (hasPermission) {
        await provider.fetchUsageData();
        debugPrint('✅ WorkManager: fetchUsageData selesai di background');

        // Notif "sudah memperbarui data" HANYA sekali setelah reboot,
        // bukan tiap 15 menit. BootReceiver menyetel flag just_booted=true
        // saat perangkat menyala; di sini flag dicek lalu langsung di-reset.
        bool justBooted = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          justBooted = prefs.getBool('just_booted') ?? false;
          if (justBooted) {
            await prefs.setBool('just_booted', false);
          }
        } catch (_) {}

        if (justBooted) {
          final statusStr = provider._prediction == 1 ? '⚠️ Bahaya' : '✅ Aman';
          final screenStr = provider._data.dailyScreenTime.toStringAsFixed(1);
          final notifCount = provider._data.notifications;
          await provider._notificationsPlugin.show(
            1002,
            'Jeda sudah memperbarui data',
            'Status: $statusStr · ${screenStr}j layar · $notifCount notif',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'jeda_calc_channel',
                'Jeda - Pembaruan Data',
                channelDescription:
                    'Notifikasi saat Jeda memperbarui data penggunaan di background',
                importance: Importance.low,
                priority: Priority.low,
                autoCancel: true,
                onlyAlertOnce: true,
                icon: '@mipmap/ic_launcher',
              ),
            ),
          );
        }
      } else {
        debugPrint('⚠️ WorkManager: permission belum ada, skip fetch');
      }
    } catch (e) {
      debugPrint('❌ WorkManager task gagal: $e');
    }
    return Future.value(true);
  });
}

// ═══════════════════════════════════════════════════════════════════
// TAMBAHAN: struktur data & helper untuk merekonstruksi JAM PERSIS
// kapan suatu threshold (screen time, sosmed, malam) terlampaui,
// berdasarkan histori event kronologis — bukan waktu evaluasi.
// ═══════════════════════════════════════════════════════════════════
class _UsageInterval {
  final int startMs;
  final int endMs;
  final bool isSocial;
  const _UsageInterval(this.startMs, this.endMs, this.isSocial);
}

// Mengembalikan sub-interval (start,end) dari overlap sesi [sStart,sEnd]
// dengan jendela malam — mirror persis logic _intersectWithNight, tapi
// mengembalikan rentang waktu aktual, bukan cuma total durasi ms.
List<_UsageInterval> _nightOverlapIntervals(
  DateTime sStart,
  DateTime sEnd,
  DateTime n1Start,
  DateTime n1End,
  DateTime n2Start,
  DateTime now,
) {
  final result = <_UsageInterval>[];

  final i1Start = sStart.isAfter(n1Start) ? sStart : n1Start;
  final i1End = sEnd.isBefore(n1End) ? sEnd : n1End;
  if (i1Start.isBefore(i1End)) {
    result.add(_UsageInterval(
      i1Start.millisecondsSinceEpoch,
      i1End.millisecondsSinceEpoch,
      false,
    ));
  }

  if (now.isAfter(n2Start)) {
    final i2Start = sStart.isAfter(n2Start) ? sStart : n2Start;
    final i2End = sEnd.isBefore(now) ? sEnd : now;
    if (i2Start.isBefore(i2End)) {
      result.add(_UsageInterval(
        i2Start.millisecondsSinceEpoch,
        i2End.millisecondsSinceEpoch,
        false,
      ));
    }
  }

  return result;
}

// Sweep kronologis: urutkan interval berdasarkan waktu mulai, akumulasi
// durasi, dan cari titik PERSIS kapan akumulasi menembus thresholdHours.
// Karena penggunaan dalam satu sesi foreground itu kontinu, interpolasi
// linear di dalam interval yang menembus threshold itu tepat secara
// matematis, bukan sekadar estimasi kasar.
DateTime? _findCrossingTime(
  List<_UsageInterval> intervals,
  double thresholdHours, {
  bool socialOnly = false,
}) {
  final relevant = socialOnly
      ? intervals.where((i) => i.isSocial).toList()
      : List<_UsageInterval>.from(intervals);

  relevant.sort((a, b) => a.startMs.compareTo(b.startMs));

  final thresholdMs = thresholdHours * 3600000;
  double running = 0;

  for (final interval in relevant) {
    final duration = (interval.endMs - interval.startMs).toDouble();
    if (duration <= 0) continue;

    if (running + duration >= thresholdMs) {
      final crossingMs = interval.startMs + (thresholdMs - running).round();
      return DateTime.fromMillisecondsSinceEpoch(crossingMs);
    }
    running += duration;
  }

  return null; // Threshold belum tentu terlampaui di data yang tersedia
}

class AppProvider extends ChangeNotifier {
  UsageData _data = UsageData();
  NaiveBayesModel? _model;
  int _prediction = 0;
  double _addictionProb = 0;
  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool get isInitialLoading => _isInitialLoading;
  bool _hasPermission = false;
  bool _isMonitoringEnabled = true;
  bool _isSoundEnabled = true;
  bool _initialized = false;
  bool _appNamesLoaded = false;
  bool _notifListenerActive = false;
  Map<String, double> _appUsageMap = {};
  Map<String, String> _appNameMap = {};
  Map<String, int> _appCategoryMap = {};
  Set<String> _launchablePackages = {};

  Map<String, double> get appUsageMap => _appUsageMap;
  Map<String, String> get appNameMap => _appNameMap;
  Map<String, int> get appCategoryMap => _appCategoryMap;
  Timer? _midnightTimer;
  Timer? _pollingTimer;
  Timer? _monitoringSyncTimer;
  Timer? _overlayRequestTimer;

  bool _isWarningOpen = false;
  bool _isResuming = false; // ← TAMBAH INI
  Timer? _snoozeTimer;

  String _alarmSound = 'alarm';
  String _vibrationMode = 'pendek';
  int _motivationVariant = 0;

  String get alarmSound => _alarmSound;
  String get vibrationMode => _vibrationMode;
  int get motivationVariant => _motivationVariant;

  static const List<String> motivationTexts = [
    'Pola penggunaanmu sudah\nberlebihan.\nMata dan pikiranmu butuh\nistirahat.',
    'Sudah waktunya istirahat.\nBeri matamu kesempatan\nuntuk rileks sejenak.',
    'Tubuhmu butuh gerak.\nYuk, bangun dan\nregangkan badan dulu.',
    'Terlalu lama di layar\nbisa bikin pikiran lelah.\nAmbil napas, dan jeda dulu.',
  ];

  static const List<IconData> motivationIcons = [
    Icons.wb_sunny_rounded,
    Icons.self_improvement_rounded,
    Icons.directions_walk_rounded,
    Icons.air_rounded,
  ];
  static const List<Color> motivationColors = [
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFF6366F1),
  ];

  String getMotivationText() {
    return motivationTexts[getMotivationIndex()];
  }

  // Mengembalikan index pesan yang dipakai (0..n-1). Dipakai untuk memilih
  // logo & warna yang konsisten dengan pilihan di halaman Pengaturan. Untuk
  // mode acak (variant 0) index dipilih random SEKALI dan disimpan agar teks,
  // logo, dan warna yang dikirim ke overlay konsisten satu sama lain.
  int _lastMotivationIndex = 0;
  int getMotivationIndex() {
    if (_motivationVariant == 0) {
      _lastMotivationIndex = Random().nextInt(motivationTexts.length);
    } else {
      _lastMotivationIndex =
          (_motivationVariant - 1).clamp(0, motivationTexts.length - 1);
    }
    return _lastMotivationIndex;
  }

  final Map<String, String> _logFirstDetectedTime = {};

  // ═══ TAMBAHAN: jam AKURAT (hasil rekonstruksi kronologis) per kondisi ═══
  final Map<String, DateTime> _thresholdCrossingTime = {};

  final List<Map<String, dynamic>> _detectionLogs = [];
  List<Map<String, dynamic>> get detectionLogs => _detectionLogs;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _dialogAlarmPlayer = AudioPlayer();
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  final Map<String, DateTime> _notifHashTime = {};
  static const Duration _notifHashWindow = Duration(seconds: 1);

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

      final Map<String, int> countPerPkg = {};
      int count = 0;

      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        if (et != 12) continue;
        final pkg = e.packageName ?? '';
        if (pkg.isEmpty || !_launchablePackages.contains(pkg)) continue;
        count++;
        countPerPkg[pkg] = (countPerPkg[pkg] ?? 0) + 1;
      }

      countPerPkg.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..forEach((e) => debugPrint('  📬 ${e.value}x │ ${e.key}'));

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

    // Reset penanda "monitoring dimatikan hari ini" bila sudah ganti hari.
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month}-${today.day}';
      final savedDay = prefs.getString('disabled_day_marker');
      if (savedDay != todayStr) {
        await prefs.setBool('monitoring_disabled_today', false);
        await prefs.setString('disabled_day_marker', todayStr);
        try {
          await platform.invokeMethod('resetDisabledToday');
        } catch (_) {}
        debugPrint('🔄 Hari baru — reset monitoring_disabled_today.');
      }
    } catch (_) {}

    // Load _launchablePackages PALING AWAL — _countMissedNotifications
    // dan notification listener bergantung pada ini untuk filter,
    // jika dipanggil belakangan filter akan kosong dan memblokir semua notif.
    await _loadAppNames();

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
    _alarmSound = prefs.getString('alarm_sound') ?? 'alarm';
    _vibrationMode = prefs.getString('vibration_mode') ?? 'pendek';
    _motivationVariant = prefs.getInt('motivation_variant') ?? 0;

    if (lastDate == todayStr) {
      final savedCount = prefs.getInt('notif_count') ?? 0;
      final eventCount = await _countMissedNotifications(startOfDay);
      final adjustedEventCount = (eventCount * 1.15).round();

      final isStale =
          savedCount > adjustedEventCount * 3 && adjustedEventCount > 5;
      _data.notifications = isStale
          ? adjustedEventCount
          : (savedCount > adjustedEventCount ? savedCount : adjustedEventCount);
      await prefs.setInt('notif_count', _data.notifications);
      debugPrint(
          '📊 Notif restore: saved=$savedCount, events=$eventCount, stale=$isStale, pakai=${_data.notifications}');
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

    _listenOverlayEvents();

    // CATATAN: warm-up overlay dihapus karena menyebabkan alarm berbunyi
    // saat aplikasi baru dibuka (overlay kini membunyikan alarm sendiri).

    // ══════════════════════════════════════════════════════════
    // WORKMANAGER — daftarkan task periodik (min. 15 menit, batas
    // Android) yang menjalankan ulang fetchUsageData() di background,
    // supaya kondisi blocking tidak "membeku" lama setelah HP restart
    // tanpa app dibuka. Pakai existingWorkPolicy.replace supaya tidak
    // dobel-daftar tiap kali initialize() jalan.
    try {
      await Workmanager().registerPeriodicTask(
        'jeda_periodic_fetch',
        'fetchUsageDataTask',
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint('✅ WorkManager periodic task terdaftar');
    } catch (e) {
      debugPrint('❌ Gagal daftarkan WorkManager task: $e');
    }

    _scheduleMidnightReset();
    _startUsagePolling();

    if (_hasPermission) await fetchUsageData();

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
      bool isGranted =
          (await NotificationListenerService.isPermissionGranted()) ?? false;
      if (!isGranted) {
        await NotificationListenerService.requestPermission();
        isGranted =
            (await NotificationListenerService.isPermissionGranted()) ?? false;
      }
      if (!isGranted) {
        debugPrint('⚠️ Izin notifikasi tidak diberikan');
        return;
      }

      NotificationListenerService.notificationsStream.listen((event) async {
        final pkg = event.packageName ?? '';

        if (pkg.isEmpty || !_launchablePackages.contains(pkg)) return;

        final hasRemoved = event.hasRemoved ?? false;
        if (hasRemoved) return;

        final title = event.title ?? '';
        final body = event.content ?? '';
        final isSummaryByPattern = RegExp(
              r'^\d+\s+(pesan|messages?|notifikasi|new)',
              caseSensitive: false,
            ).hasMatch(title) ||
            RegExp(r'^\(\d+\)').hasMatch(title);
        if (isSummaryByPattern) {
          debugPrint('🔕 Skip summary notif: $pkg | title=$title');
          return;
        }

        final hashKey = '$pkg|$title|$body';
        final nowTime = DateTime.now();
        final lastHashTime = _notifHashTime[hashKey];
        if (lastHashTime != null &&
            nowTime.difference(lastHashTime) < _notifHashWindow) {
          debugPrint('🔕 Dedup hash: $hashKey');
          return;
        }
        _notifHashTime[hashKey] = nowTime;

        _data.notifications += 1;
        await prefs.setInt('notif_count', _data.notifications);
        debugPrint(
            '🔔 Notif [+1]: $pkg | Total: ${_data.notifications} | hash: $hashKey');
        _runPrediction(allowWarning: false);
        notifyListeners();
      });

      _notifListenerActive = true;
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

  Future<void> _deleteChannel(String soundKey, String vibKey) async {
    try {
      final id = 'jeda_alarm_${soundKey}_$vibKey';
      final android =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.deleteNotificationChannel(id);
    } catch (e) {
      debugPrint('❌ deleteChannel: $e');
    }
  }

  Future<void> setAlarmSound(String value) async {
    await _deleteChannel(_alarmSound, _vibrationMode);
    _alarmSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_sound', value);
    notifyListeners();
  }

  Future<void> setVibrationMode(String value) async {
    await _deleteChannel(_alarmSound, _vibrationMode);
    _vibrationMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vibration_mode', value);
    notifyListeners();
  }

  Future<void> setMotivationVariant(int value) async {
    _motivationVariant = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('motivation_variant', value);
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
      _notifHashTime.clear();
      _detectionLogs.clear();
      _logFirstDetectedTime.clear();
      _thresholdCrossingTime.clear(); // ← TAMBAHAN: reset jam akurat hari baru

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

  void _cleanupNotifHashMap() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _notifHashTime.removeWhere((_, time) => time.isBefore(cutoff));
  }

  void _startUsagePolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_hasPermission) {
        await fetchUsageData();
        debugPrint('🔁 Auto-refresh usage data');
      }
      _cleanupNotifHashMap();
    });
    debugPrint('✅ Polling timer aktif (interval: 5 menit)');

    // Timer cepat untuk menyinkronkan status monitoring dari native. Jika
    // monitoring dimatikan lewat overlay (native menulis
    // monitoring_disabled_today=true), toggle dashboard ikut OFF tanpa perlu
    // menunggu app di-resume atau polling 5 menit.
    _monitoringSyncTimer?.cancel();
    _monitoringSyncTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final disabled = prefs.getBool('monitoring_disabled_today') ?? false;
        if (disabled && _isMonitoringEnabled) {
          _isMonitoringEnabled = false;
          notifyListeners();
          debugPrint('🔁 UI: monitoring disinkronkan OFF (dari overlay).');
        }
      } catch (_) {}
    });
    _overlayRequestTimer?.cancel();
    _overlayRequestTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        if (prefs.getBool('request_show_overlay') ?? false) {
          await prefs.setBool('request_show_overlay', false);
          await showJedaOverlay();
        }
      } catch (_) {}
    });
  }

  Future<void> fetchUsageData() async {
    _isLoading = true;
    notifyListeners();
    if (!_appNamesLoaded) {
      await _loadAppNames();
    }

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final startOfDayMs = startOfDay.millisecondsSinceEpoch;
      final nowMs = now.millisecondsSinceEpoch;

      final windowStart = DateTime(now.year, now.month, now.day - 1, 20, 0, 0);

      // Identifikasi sosial media menggunakan ApplicationInfo.CATEGORY_SOCIAL (nilai 4)
      // dari Android API — ditetapkan oleh developer aplikasi masing-masing.
      // Referensi: Android Developer Documentation (ApplicationInfo.CATEGORY_SOCIAL);
      // Woodward et al. (2025), J. technol. behav. sci., DOI: 10.1007/s41347-024-00474-y;
      // Khalaida et al. (2025), JATI Vol.9 No.5.
      bool isSocialMedia(String pkg) => (_appCategoryMap[pkg] ?? -1) == 4;

      bool isSystemPackage(String pkg) {
        return !_launchablePackages.contains(pkg);
      }

      final allEvents = ((await UsageStats.queryEvents(windowStart, now)) ?? [])
          .cast<EventUsageInfo>()
          .toList();

      final List<int> screenOffTimestamps = [];
      int screenUnlockCount = 0;
      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        final pkg = e.packageName ?? '';
        if (pkg != 'android') continue;
        final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
        if (et == 2 || et == 15) {
          screenOffTimestamps.add(tsMs);
        }
        if (et == 18 && tsMs >= startOfDayMs) {
          screenUnlockCount++;
        }
      }
      debugPrint('🔓 Screen unlocks: $screenUnlockCount');

      final Map<String, int> foregroundStart = {};
      final Map<String, double> eventsDuration = {};
      final Set<String> appsWithActivityToday = {};

      // ═══ TAMBAHAN: kumpulkan interval mentah buat sweep kronologis ═══
      final List<_UsageInterval> screenIntervals = [];

      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        final pkg = e.packageName ?? '';
        if (pkg.isEmpty || isSystemPackage(pkg)) continue;
        if (et != 1 && et != 2) continue;

        final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;

        if (et == 1) {
          foregroundStart[pkg] = tsMs;
        } else if (et == 2) {
          final startMs = foregroundStart[pkg];
          if (startMs == null) continue;

          if (startMs >= startOfDayMs) {
            final duration = tsMs - startMs;
            if (duration > 0 && duration <= 7200000) {
              eventsDuration[pkg] = (eventsDuration[pkg] ?? 0) + duration;
              appsWithActivityToday.add(pkg);
              // ═ TAMBAHAN ═
              screenIntervals.add(
                  _UsageInterval(startMs, tsMs, isSocialMedia(pkg)));
            }
          } else if (tsMs >= startOfDayMs) {
            final screenOffBetween = screenOffTimestamps
                .where((t) => t > startMs && t < tsMs)
                .toList()
              ..sort();

            final int effectiveEnd;
            if (screenOffBetween.isNotEmpty) {
              effectiveEnd = screenOffBetween.first;
            } else {
              effectiveEnd = tsMs;
            }

            if (effectiveEnd > startOfDayMs) {
              final durationToday = effectiveEnd - startOfDayMs;
              if (durationToday > 0 && durationToday <= 14400000) {
                eventsDuration[pkg] =
                    (eventsDuration[pkg] ?? 0) + durationToday;
                appsWithActivityToday.add(pkg);
                debugPrint(
                    '🌙 Split midnight: $pkg +${(durationToday / 60000).toStringAsFixed(1)}m');
                // ═ TAMBAHAN ═
                screenIntervals.add(_UsageInterval(
                    startOfDayMs, effectiveEnd, isSocialMedia(pkg)));
              }
            }
          }
          foregroundStart.remove(pkg);
        }
      }

      foregroundStart.forEach((pkg, startMs) {
        final hasScreenOffAfterStart =
            screenOffTimestamps.any((t) => t > startMs);
        if (hasScreenOffAfterStart) return;

        final int effectiveStart =
            startMs < startOfDayMs ? startOfDayMs : startMs;
        final duration = nowMs - effectiveStart;

        if (duration > 0 && duration <= 1800000) {
          eventsDuration[pkg] =
              (eventsDuration[pkg] ?? 0) + duration.toDouble();
          appsWithActivityToday.add(pkg);
          // ═ TAMBAHAN ═
          screenIntervals
              .add(_UsageInterval(effectiveStart, nowMs, isSocialMedia(pkg)));
        }
      });

      eventsDuration.forEach((pkg, ms) {
        debugPrint('  📱 events: ${(ms / 3600000).toStringAsFixed(2)}j │ $pkg');
      });

      double queryStatsTotalMs = 0;
      try {
        final usageStatsList =
            await UsageStats.queryUsageStats(startOfDay, now);
        if (usageStatsList != null) {
          for (final stat in usageStatsList) {
            final pkg = stat.packageName ?? '';
            if (pkg.isEmpty || isSystemPackage(pkg)) continue;
            final totalTime =
                int.tryParse(stat.totalTimeInForeground?.toString() ?? '0') ??
                    0;
            if (totalTime > 0) {
              queryStatsTotalMs += totalTime;
              debugPrint(
                  '  📊 queryStats (ref): ${(totalTime / 3600000).toStringAsFixed(2)}j │ $pkg');
            }
          }
        }
        debugPrint(
            '📊 queryStats TOTAL (ref): ${(queryStatsTotalMs / 3600000).toStringAsFixed(2)}j');
      } catch (e) {
        debugPrint('⚠️ queryUsageStats error: $e');
      }

      double reconciledTotal = 0;
      double reconciledSocial = 0;

      for (final pkg in appsWithActivityToday) {
        if (isSystemPackage(pkg)) continue;

        final chosen = eventsDuration[pkg] ?? 0.0;
        if (chosen <= 0) continue;

        reconciledTotal += chosen;
        if (isSocialMedia(pkg)) reconciledSocial += chosen;
      }

      debugPrint(
          '⚖️ Rekonsiliasi: ${(reconciledTotal / 3600000).toStringAsFixed(2)}j');

      _appUsageMap = {};
      for (final pkg in appsWithActivityToday) {
        if (isSystemPackage(pkg)) continue;
        if (pkg == 'android') continue;
        if (!pkg.contains('.')) continue;
        final chosen = eventsDuration[pkg] ?? 0.0;
        if (chosen > 0) {
          _appUsageMap[pkg] = chosen / 3600000.0;
        }
      }

      double nightScreenMs = 0.0;
      final nightStart1 = DateTime(now.year, now.month, now.day - 1, 22, 0, 0);
      final nightEnd1 = DateTime(now.year, now.month, now.day, 5, 0, 0);
      final nightStart2 = DateTime(now.year, now.month, now.day, 22, 0, 0);
      final Map<String, int?> foregroundTimestamp = {};

      // ═══ TAMBAHAN: kumpulkan interval overlap malam buat sweep kronologis ═══
      final List<_UsageInterval> nightIntervals = [];

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
            // ═ TAMBAHAN ═
            nightIntervals.addAll(_nightOverlapIntervals(
              DateTime.fromMillisecondsSinceEpoch(startMs),
              eventTime,
              nightStart1,
              nightEnd1,
              nightStart2,
              now,
            ));
            foregroundTimestamp.remove(pkg);
          }
        }
      }

      foregroundTimestamp.forEach((pkg, startMs) {
        if (startMs == null) return;
        final screenOffAfter =
            screenOffTimestamps.where((t) => t > startMs).toList()..sort();
        final effectiveEnd = screenOffAfter.isNotEmpty
            ? DateTime.fromMillisecondsSinceEpoch(screenOffAfter.first)
            : now;
        nightScreenMs += _intersectWithNight(
          DateTime.fromMillisecondsSinceEpoch(startMs),
          effectiveEnd,
          nightStart1,
          nightEnd1,
          nightStart2,
          now,
        );
        // ═ TAMBAHAN ═
        nightIntervals.addAll(_nightOverlapIntervals(
          DateTime.fromMillisecondsSinceEpoch(startMs),
          effectiveEnd,
          nightStart1,
          nightEnd1,
          nightStart2,
          now,
        ));
      });

      final screenHours = reconciledTotal / 3600000.0;
      final socialHours = reconciledSocial / 3600000.0;
      final nightUsageHours = nightScreenMs / 3600000.0;

      // ═══════════════════════════════════════════════════════════════
      // TAMBAHAN: hitung JAM PERSIS kapan tiap threshold terlampaui,
      // simpan ke _thresholdCrossingTime. Hanya di-set kalau memang
      // sudah terlampaui HARI INI, dan hanya SEKALI (tidak ditimpa ulang
      // di re-fetch berikutnya pada hari yang sama).
      // ═══════════════════════════════════════════════════════════════
      if (screenHours > 4.0 &&
          !_thresholdCrossingTime.containsKey('screen_time_tinggi')) {
        final t = _findCrossingTime(screenIntervals, 4.0);
        if (t != null) _thresholdCrossingTime['screen_time_tinggi'] = t;
      }
      if (socialHours > 5.0 &&
          !_thresholdCrossingTime.containsKey('sosmed_berlebihan')) {
        final t = _findCrossingTime(screenIntervals, 5.0, socialOnly: true);
        if (t != null) _thresholdCrossingTime['sosmed_berlebihan'] = t;
      }
      if (nightUsageHours > 2.3 &&
          !_thresholdCrossingTime.containsKey('penggunaan_malam')) {
        final t = _findCrossingTime(nightIntervals, 2.3);
        if (t != null) _thresholdCrossingTime['penggunaan_malam'] = t;
      }

      debugPrint('════════════════════════════════════');
      debugPrint('📊 RINGKASAN USAGE DATA');
      debugPrint('   Screen Time  : ${screenHours.toStringAsFixed(2)}j');
      debugPrint(
          '   queryStats   : ${(queryStatsTotalMs / 3600000).toStringAsFixed(2)}j (ref)');
      debugPrint('   Sessions     : $screenUnlockCount');
      debugPrint('   Night Usage  : ${nightUsageHours.toStringAsFixed(2)}j');
      debugPrint('   Social       : ${socialHours.toStringAsFixed(2)}j');
      debugPrint('   Notif        : ${_data.notifications}');
      debugPrint('════════════════════════════════════');

      _data = UsageData(
        dailyScreenTime: screenHours,
        appSessions: screenUnlockCount,
        socialMediaUsage: socialHours,
        gamingTime: 0,
        notifications: _data.notifications,
        nightUsage: nightUsageHours,
        appsInstalled: 0,
      );

      _runPrediction();
    } catch (e, st) {
      debugPrint('❌ fetchUsageData error: $e\n$st');
    }

    _isLoading = false;
    _isInitialLoading = false;
    notifyListeners();
  }

  void _generateDetectionLogs() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // ═ TAMBAHAN: format DateTime jadi HH:mm untuk jam akurat ═
    String formatTime(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    void addLog(String key, Map<String, dynamic> log, {String? timeOverride}) {
      final exists = _detectionLogs.any((l) => l['key'] == key);
      if (!exists) {
        final resolvedTime = timeOverride ?? timeStr;
        if (!_logFirstDetectedTime.containsKey(key)) {
          _logFirstDetectedTime[key] = resolvedTime;
        }
        final firstTime = _logFirstDetectedTime[key] ?? resolvedTime;
        _detectionLogs.add({...log, 'key': key, 'time': firstTime});
      }
    }

    // ─── LOG 1: Status Model (Kwon et al., 2013 — SAS-SV) ───────────────────
    // Trigger: _prediction == 1 (at risk/addicted berdasarkan SAS-SV)
    // Kwon hanya menghasilkan 2 label (0 = normal, 1 = at risk/addicted).
    // CATATAN: TETAP pakai waktu evaluasi (timeStr/now), BUKAN jam akurat —
    // karena ini hasil kombinasi probabilistik 3 fitur sekaligus (Naive
    // Bayes joint prediction), bukan threshold tunggal pada satu angka
    // akumulatif, sehingga tidak ada "titik crossing" tunggal yang
    // well-defined secara matematis untuk direkonstruksi.
    if (_prediction == 1) {
      addLog('status_adiksi', {
        'title': 'Terdeteksi Risiko Adiksi Smartphone',
        'desc':
            'Pola penggunaan harianmu (durasi layar, frekuensi buka HP, dan notifikasi) menunjukkan indikasi adiksi smartphone berdasarkan Smartphone Addiction Scale — Short Version.',
        'color': const Color(0xFFEF4444),
        'icon': Icons.warning_rounded,
        'source': 'Kwon et al., 2013 — SAS-SV (PLoS ONE). '
            'DOI: 10.1371/journal.pone.0083558',
      });
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'status_adiksi');
    }

    // ─── LOG 2: Sosial Media Berlebihan ──────────────────────────────────────
    // Trigger: socialMediaUsage > 5.0 jam/hari
    // Deteksi sosmed via ApplicationInfo.CATEGORY_SOCIAL (Android API).
    // Referensi klasifikasi platform: Woodward et al. (2025), J. Technol. Behav.
    // Sci., DOI: 10.1007/s41347-024-00474-y — mengklasifikasikan TikTok, Twitter,
    // YouTube, Instagram, Facebook, Snapchat, Reddit sebagai platform sosial media;
    // Khalaida et al. (2025), JATI Vol.9 No.5 — konteks Indonesia.
    // Threshold: Sert, Ünsal, Can (2026) — penggunaan sosmed ≥5 jam/hari
    // dikaitkan dengan skor adiksi lebih tinggi pada remaja SMA (n=858).
    // Waktu yang dicatat: JAM AKURAT hasil sweep kronologis (bukan waktu
    // evaluasi), lihat _thresholdCrossingTime & fetchUsageData().
    if (_data.socialMediaUsage > 5.0) {
      final crossing = _thresholdCrossingTime['sosmed_berlebihan'];
      addLog(
        'sosmed_berlebihan',
        {
          'title': 'Penggunaan Sosial Media Berlebihan',
          'desc':
              'Penggunaan sosial media hari ini melebihi 5 jam. Remaja yang menggunakan sosial media ≥5 jam per hari menunjukkan skor adiksi smartphone yang lebih tinggi.',
          'color': const Color(0xFFEC4899),
          'icon': Icons.tag_rounded,
          'source': 'Sert, Ünsal & Can, 2026 — Journal of Community Health. '
              'DOI: 10.1007/s10900-026-01578-7',
        },
        timeOverride: crossing != null ? formatTime(crossing) : null,
      );
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'sosmed_berlebihan');
    }

    // ─── LOG 3: Screen Time Tinggi ───────────────────────────────────────────
    // Trigger: dailyScreenTime > 4.0 jam/hari
    // Landasan: Dai & Ouyang (2026) — screen time ≥4 jam/hari berkaitan dengan
    // risiko lebih tinggi untuk kecemasan (aOR=1.45), depresi (aOR=1.61),
    // masalah perilaku (aOR=1.24), dan ADHD (aOR=1.21) pada anak dan remaja AS.
    // Waktu yang dicatat: JAM AKURAT hasil sweep kronologis.
    if (_data.dailyScreenTime > 4.0) {
      final crossing = _thresholdCrossingTime['screen_time_tinggi'];
      addLog(
        'screen_time_tinggi',
        {
          'title': 'Screen Time Harian Tinggi',
          'desc':
              'Total waktu layar hari ini melebihi 4 jam. Penggunaan layar ≥4 jam per hari berkaitan dengan peningkatan risiko kecemasan, depresi, dan masalah perilaku pada remaja.',
          'color': const Color(0xFFF97316),
          'icon': Icons.phonelink_rounded,
          'source':
              'Dai & Ouyang, 2026 — Humanities & Social Sciences Communications. '
                  'DOI: 10.1057/s41599-026-06609-1',
        },
        timeOverride: crossing != null ? formatTime(crossing) : null,
      );
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'screen_time_tinggi');
    }

    // ─── LOG 4: Penggunaan Malam ─────────────────────────────────────────────
    // Trigger: nightUsage > 2.3 jam (di atas rata-rata durasi pakai HP
    // di tempat tidur pada remaja menurut Bozkurt et al., 2024)
    // Landasan 1: Bozkurt et al. (2024) — rata-rata durasi pakai HP di tempat
    // tidur 2,3 jam/hari; durasi lebih panjang berkaitan positif dengan kualitas
    // tidur buruk pada remaja 13–18 tahun. DOI: 10.5152/eurasianjmed.2024.23379
    // Landasan 2: Dutil et al. (2022) — waktu tidur setelah pukul 22:00
    // dikaitkan dengan peningkatan gejala depresi dan performa akademik lebih
    // rendah pada remaja. DOI: 10.24095/hpcdp.42.4.04
    // nightUsage = total durasi pakai HP antara 22:00–05:00 (proxy operasional).
    // Waktu yang dicatat: JAM AKURAT hasil sweep kronologis.
    if (_data.nightUsage > 2.3) {
      final crossing = _thresholdCrossingTime['penggunaan_malam'];
      addLog(
        'penggunaan_malam',
        {
          'title': 'Penggunaan Smartphone Malam Hari Tinggi',
          'desc':
              'Penggunaan smartphone antara pukul 22:00–05:00 melebihi 2,3 jam. Durasi ini di atas rata-rata remaja dan berkaitan dengan kualitas tidur buruk serta peningkatan risiko depresi.',
          'color': const Color(0xFF6366F1),
          'icon': Icons.nightlight_rounded,
          'source': 'Bozkurt et al., 2024 — Eurasian Journal of Medicine. '
              'DOI: 10.5152/eurasianjmed.2024.23379 | '
              'Dutil et al., 2022 — Health Promot. Chronic Dis. Prev. Can. '
              'DOI: 10.24095/hpcdp.42.4.04',
        },
        timeOverride: crossing != null ? formatTime(crossing) : null,
      );
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'penggunaan_malam');
    }
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
    try {
      await platform.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<void> onAppResumed() async {
  if (_isResuming) return; 
  _isResuming = true;       
  debugPrint('🔄 App resumed — re-cek permission');

     // Sinkronkan status monitoring dari native/overlay — pakai flag yang
  // SPESIFIK merepresentasikan "user mematikan monitoring", bukan
  // getBlockingStatus yang ambigu (bisa juga berarti prediksi lagi aman).
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final disabledByUser = prefs.getBool('monitoring_disabled_today') ?? false;
    if (disabledByUser && _isMonitoringEnabled) {
      _isMonitoringEnabled = false;
      notifyListeners();
      debugPrint('🔁 Monitoring disinkronkan OFF (user matikan via overlay).');
    }
  } catch (_) {}

    if (!_notifListenerActive) {
      final prefs = await SharedPreferences.getInstance();
      await _initNotificationListener(prefs);
    }

    final bool hadPermissionBefore = _hasPermission;

    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }

    debugPrint('🔑 hasPermission setelah resume: $_hasPermission');
    debugPrint('🔑 initialized: $_initialized');

    // Jika permission Usage Stats BARU saja diberikan (transisi
    // false -> true), _countMissedNotifications() di initialize()
    // kemungkinan gagal total karena dijalankan sebelum izin ada.
    // Hitung ulang notif sekarang supaya tidak nyangkut di 0.
    if (_hasPermission && !hadPermissionBefore) {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final eventCount = await _countMissedNotifications(startOfDay);
      final adjustedEventCount = (eventCount * 1.15).round();
      if (adjustedEventCount > _data.notifications) {
        _data.notifications = adjustedEventCount;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('notif_count', _data.notifications);
        debugPrint('📬 Notif dihitung ulang setelah permission baru: ${_data.notifications}');
      }
    }

    if (_hasPermission) {
      try {
        await fetchUsageData();
      } catch (e) {
        debugPrint('❌ fetchUsageData di resume gagal: $e');
      }
    }

    notifyListeners();
    debugPrint('🔔 notifyListeners dipanggil');
    _isResuming = false; // ← TAMBAH INI
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
    final bool hadPermissionBefore = _hasPermission;
    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }

    if (_hasPermission && !hadPermissionBefore) {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final eventCount = await _countMissedNotifications(startOfDay);
      final adjustedEventCount = (eventCount * 1.15).round();
      if (adjustedEventCount > _data.notifications) {
        _data.notifications = adjustedEventCount;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('notif_count', _data.notifications);
        debugPrint('📬 Notif dihitung ulang setelah permission baru (checkPermission): ${_data.notifications}');
      }
      await fetchUsageData();
    }
    notifyListeners();
  }

  void _listenOverlayEvents() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) async {
        debugPrint('🎯 OVERLAY EVENT DITERIMA: $event');
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

  Future<void> stopForegroundService() async {
    try {
      await platform.invokeMethod('stopForegroundService');
    } catch (e) {
      debugPrint('❌ Gagal stop foreground service: $e');
    }
  }

  Future<void> setMonitoring(bool value) async {
    _isMonitoringEnabled = value;
    notifyListeners();
    if (!value) await _stopDialogAlarm();
    // Reset/set penanda "dimatikan hari ini" agar konsisten dengan native.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_disabled_today', !value);
      await prefs.reload();
      if (value) {
        debugPrint('✅ Monitoring ON — reset monitoring_disabled_today=false');
      }
    } catch (_) {}
    if (!value) {
      await _syncBlockerToNative(false);
      await _notificationsPlugin.cancel(999);
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
    } else {
      // Saat monitoring dinyalakan kembali, evaluasi ulang kondisi
      // TERKINI (bukan cuma sync status prediksi lama) — supaya kalau
      // pemakaian sudah berada di kondisi BAHAYA sejak sebelum
      // monitoring dimatikan, peringatan langsung muncul lagi, bukan
      // menunggu siklus polling/WorkManager berikutnya.
      if (_hasPermission) {
        await fetchUsageData();
      } else if (_prediction == 1) {
        await _syncBlockerToNative(true);
      }
    }
  }

  Future<void> showJedaOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) return; // hindari dobel
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        overlayTitle: 'Saatnya Jeda',
        overlayContent: 'Pola penggunaanmu sudah berlebihan',
        flag: OverlayFlag.defaultFlag,
        alignment: OverlayAlignment.topLeft,
        height: WindowSize.matchParent,
        width: WindowSize.matchParent,
      );
      // Kirim SEMUA konfigurasi ke isolate overlay via shareData. Ini memakai
      // nilai dari AppProvider (isolate utama) yang selalu terbaru, sehingga
      // menghindari masalah SharedPreferences yang tidak tersinkron antar
      // isolate (isolate overlay punya cache prefs sendiri). shareData juga
      // menjadi sinyal bahwa ini peringatan NYATA (bukan re-attach startup),
      // sehingga alarm hanya berbunyi saat memang dipicu deteksi Bahaya.
      await Future.delayed(const Duration(milliseconds: 200));
      final msgIndex = getMotivationIndex();
      await FlutterOverlayWindow.shareData({
        'action': 'alarm',
        'sound_enabled': _isSoundEnabled,
        'alarm_sound': _alarmSound,
        'vibration_mode': _vibrationMode,
        'message': motivationTexts[msgIndex],
        'variant_index': msgIndex,
      });
    } catch (e) {
      debugPrint('❌ showJedaOverlay: $e');
    }
  }

  Future<void> _syncBlockerToNative(bool status) async {
    try {
      await platform.invokeMethod('setBlockingStatus', {'status': status});
    } on MissingPluginException catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isBlockingActive_bg', status);
        debugPrint('✅ Sync native (fallback background): $status');
      } catch (e2) {
        debugPrint('❌ Fallback sync native gagal: $e2');
      }
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
    // Jika izin overlay tersedia, pemblokiran ditangani sepenuhnya oleh
    // overlay window. Redirect native TIDAK dijalankan agar tidak terjadi
    // pemblokiran ganda. Redirect hanya fallback saat izin overlay tak ada.
    try {
      final overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (overlayGranted) {
        debugPrint('⏭️ enforceBlock: overlay aktif, redirect di-skip.');
        return;
      }
    } catch (_) {}
    try {
      await platform.invokeMethod('enforceBlockIfNecessary');
    } catch (e) {
      debugPrint('❌ enforceBlock: $e');
    }
  }

  // Helper: cek apakah sedang dalam periode snooze (baca snoozeUntil dari
  // native JedaPrefs). Dipakai di banyak titik agar snooze selalu dihormati,
  // termasuk saat notif masuk memicu evaluasi ulang.
  Future<bool> _isSnoozing() async {
    try {
      final snoozeUntilMs =
          await platform.invokeMethod<int>('getSnoozeUntil') ?? 0;
      return DateTime.now().millisecondsSinceEpoch < snoozeUntilMs;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNotificationAlert() async {
    debugPrint('🔊 [FLUTTER] showNotificationAlert dipanggil');
    // TIDAK cek _isWarningOpen di sini (pemanggil sudah set true → alarm tak
    // akan bunyi bila dicek). Guard monitoring & snooze tetap ada.
    if (!_isMonitoringEnabled) return;
    if (await _isSnoozing()) return;

    // Alarm memakai audioplayers (bisa dihentikan saat snooze/matikan),
    // mengikuti nada di Pengaturan.
    try {
      if (_isSoundEnabled) {
        debugPrint('🔊 [FLUTTER] play: sounds/$_alarmSound.mp3');
        await _dialogAlarmPlayer.stop();
        await _dialogAlarmPlayer.setReleaseMode(ReleaseMode.stop);
        await _dialogAlarmPlayer.setVolume(1.0);
        await _dialogAlarmPlayer.play(AssetSource('sounds/$_alarmSound.mp3'));
        debugPrint('🔊 [FLUTTER] play() OK');
      }
    } catch (e) {
      debugPrint('❌ [FLUTTER] play gagal: $e');
    }

    try {
      if (_vibrationMode != 'off') {
        final hasVib = await Vibration.hasVibrator() ?? false;
        if (hasVib) {
          if (_vibrationMode == 'panjang') {
            Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1000]);
          } else {
            Vibration.vibrate(pattern: [0, 200, 100, 200]);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [FLUTTER] getar gagal: $e');
    }
  }

  Future<void> _stopDialogAlarm() async {
    try {
      await _dialogAlarmPlayer.stop();
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
  }

Future<void> resetDailyData() async {
    _detectionLogs.clear();
    _data = UsageData();
    _logFirstDetectedTime.clear();
    _thresholdCrossingTime.clear(); // ← TAMBAHAN: reset jam akurat
    _prediction = 0;
    _addictionProb = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_count', 0);
    await prefs.setBool('monitoring_disabled_today', false);
    await prefs.setBool('isBlockingActive_bg', false);
    _isMonitoringEnabled = true;
    notifyListeners();
  }

  Future<void> _loadAppNames() async {
    try {
      final List<dynamic> apps =
          await platform.invokeMethod('getInstalledApps');
      _appNameMap = {
        for (final app in apps)
          (app['packageName'] as String): (app['appName'] as String)
      };
      _appCategoryMap = {
        for (final app in apps)
          (app['packageName'] as String): (app['category'] as int? ?? -1)
      };
      _launchablePackages = {
        for (final app in apps) (app['packageName'] as String)
      };
      _launchablePackages.remove('com.wishnotregret.berijeda');
      _appNamesLoaded = true;
      debugPrint('✅ App names loaded: ${_appNameMap.length} apps');

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          'cached_launchable_packages',
          _launchablePackages.toList(),
        );
      } catch (e) {
        debugPrint('❌ Gagal cache launchable packages: $e');
      }
    } catch (e) {
      _appNamesLoaded = true;
      debugPrint('❌ Gagal load app names (method channel): $e');

      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getStringList('cached_launchable_packages');
        if (cached != null) {
          _launchablePackages = cached.toSet();
          debugPrint(
              '✅ Fallback: ${_launchablePackages.length} package dari cache');
        }
      } catch (e2) {
        debugPrint('❌ Gagal baca cache launchable packages: $e2');
      }
    }
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

  void _runPrediction({bool allowWarning = true}) {
    if (_model != null) {
      debugPrint('🧠 INPUT MODEL:');
      debugPrint(
          '   screen_time : ${_data.dailyScreenTime.toStringAsFixed(2)}j');
      debugPrint('   unlocks     : ${_data.appSessions}x');
      debugPrint('   notif       : ${_data.notifications}x');

      final result = _model!.predict([
        _data.dailyScreenTime,
        _data.appSessions.toDouble(),
        _data.notifications.toDouble(),
      ]);
      _prediction = result['prediction'];
      _addictionProb = result['probability'];
      debugPrint('🧠 Prediksi: $_prediction | Prob: $_addictionProb');
      debugPrint('   Input: screen=${_data.dailyScreenTime.toStringAsFixed(2)}j'
          ' | unlocks=${_data.appSessions}'
          ' | notif=${_data.notifications}');
    } else {
      _prediction = _data.dailyScreenTime > 5.0 ? 1 : 0;
      _addictionProb = _prediction == 1 ? 0.88 : 0.15;
    }

    _generateDetectionLogs();

    if (_prediction == 1 && _isMonitoringEnabled) {
      Future.delayed(
        const Duration(seconds: 1),
        () => _syncBlockerToNative(true),
      );
    } else {
      _syncBlockerToNative(false);
    }

    // Hanya munculkan peringatan bila diizinkan. Saat dipicu oleh
    // notifikasi yang masuk, allowWarning=false: status & UI tetap
    // diperbarui, tapi pop-up "SAATNYA JEDA!" tidak dimunculkan agar
    // tidak spam setiap ada notif. Pop-up tetap muncul dari polling
    // berkala, WorkManager, atau saat snooze berakhir.
    if (allowWarning) {
      _checkAndShowWarning();
    }
  }

  void _checkAndShowWarning() async {
  if (_prediction != 1 || !_isMonitoringEnabled || _isWarningOpen) return;

  // Kunci LANGSUNG di sini (sebelum await apapun) supaya panggilan lain
  // yang masuk hampir bersamaan (dari snooze Timer maupun onAppResumed)
  // langsung ke-block di pengecekan _isWarningOpen di atas.
  _isWarningOpen = true;

  if (await _isSnoozing()) {
    _isWarningOpen = false;
    return;
  }
  if (!_hasPermission) {
    _isWarningOpen = false;
    return;
  }
  try {
    final accOn = await isAccessibilityEnabled();
    if (!accOn) {
      _isWarningOpen = false;
      return;
    }
  } catch (_) {
    _isWarningOpen = false;
    return;
  }

  bool overlayAvailable = false;
  try {
    overlayAvailable = await FlutterOverlayWindow.isPermissionGranted();
  } catch (_) {}

  if (!overlayAvailable) {
    showNotificationAlert();
    _showGlobalWarningDialog();
  } else {
    Future.delayed(const Duration(seconds: 3), () {
      _isWarningOpen = false;
    });
  }
}

  void _showGlobalWarningDialog() async {
    // Guard: jangan spawn dialog baru kalau sudah ada
  if (navigatorKey.currentState == null) return;
  if (navigatorKey.currentState!.overlay == null) return;

  // ← TAMBAH INI: cek apakah sudah ada dialog aktif
  final bool dialogAlreadyShown = navigatorKey.currentState!.overlay!
      .context
      .findAncestorWidgetOfExactType<Dialog>() != null;
  if (dialogAlreadyShown) return;

    try {
      if (await FlutterOverlayWindow.isActive()) return;
    } catch (_) {}

    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return;

    final int mIdx = getMotivationIndex();
    final IconData mIcon = motivationIcons[mIdx];
    final Color mColor = motivationColors[mIdx];
    final String mText = motivationTexts[mIdx];

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: mColor, shape: BoxShape.circle),
                child: Icon(mIcon,
                    color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              Text('SAATNYA JEDA!',
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: mColor,
                      letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Text(
                mText,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(dialogContext, 10),
                  child: Text('Ingatkan 10 Detik Lagi',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A2E),
                      side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(dialogContext, 600),
                  child: Text('Ingatkan 10 Menit Lagi',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () async {
                  _isWarningOpen = false;
                  Navigator.pop(dialogContext);
                  await setMonitoring(false);
                  final ctx2 = navigatorKey.currentState?.context;
                  if (ctx2 != null) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      const SnackBar(
                          content: Text('Monitoring dimatikan hari ini.')),
                    );
                  }
                },
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[500]),
                    children: [
                      const TextSpan(text: 'Saya sedang produktif. '),
                      TextSpan(
                          text: 'Matikan\nmonitoring hari ini!',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applySnooze(BuildContext dialogContext, int seconds) async {
    _isWarningOpen = false;
    await _stopDialogAlarm();

    final ctx = navigatorKey.currentState?.context;
    final messenger = ctx != null ? ScaffoldMessenger.of(ctx) : null;

    Navigator.pop(dialogContext);

    await applySnoozeNative(seconds);

    if (messenger != null) {
      final label = seconds >= 60 ? '${seconds ~/ 60} menit' : '$seconds detik';
      messenger.showSnackBar(
        SnackBar(content: Text('Jeda ditunda $label. Waktu dimulai!')),
      );
    }

    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(Duration(seconds: seconds), () async {
      if (!_isMonitoringEnabled) return;
      if (_hasPermission) {
        await fetchUsageData();
      }
      if (_prediction == 1) {
        await enforceBlockIfNecessary();
        // Cukup lewat _checkAndShowWarning() sebagai satu-satunya pintu:
        // fungsi ini sudah mengecek prediction, monitoring, snooze, dan
        // guard _isWarningOpen, lalu menampilkan notif + dialog secara
        // terkontrol. Memanggil showNotificationAlert() terpisah membuat
        // notif berpotensi tampil dua kali.
        _checkAndShowWarning();
      }
    });
  }
}