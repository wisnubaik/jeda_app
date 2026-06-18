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
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usage_data.dart';
import '../models/naive_bayes_model.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'package:google_fonts/google_fonts.dart';

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

  bool _isWarningOpen = false;
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

  String getMotivationText() {
    if (_motivationVariant == 0) {
      return motivationTexts[Random().nextInt(motivationTexts.length)];
    }
    final idx = (_motivationVariant - 1).clamp(0, motivationTexts.length - 1);
    return motivationTexts[idx];
  }

  final Map<String, String> _logFirstDetectedTime = {};

  final List<Map<String, dynamic>> _detectionLogs = [];
  List<Map<String, dynamic>> get detectionLogs => _detectionLogs;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
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
        _runPrediction();
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
      double reconciledGaming = 0;

      for (final pkg in appsWithActivityToday) {
        if (isSystemPackage(pkg)) continue;

        final chosen = eventsDuration[pkg] ?? 0.0;
        if (chosen <= 0) continue;

        reconciledTotal += chosen;
        if (socialPackages.contains(pkg)) reconciledSocial += chosen;
        if (gamePackages.contains(pkg)) reconciledGaming += chosen;
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
      });

      final screenHours = reconciledTotal / 3600000.0;
      final socialHours = reconciledSocial / 3600000.0;
      final gamingHours = reconciledGaming / 3600000.0;
      final nightUsageHours = nightScreenMs / 3600000.0;

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
    _isInitialLoading = false;
    notifyListeners();
  }

  void _generateDetectionLogs() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    void addLog(String key, Map<String, dynamic> log) {
      final exists = _detectionLogs.any((l) => l['key'] == key);
      if (!exists) {
        if (!_logFirstDetectedTime.containsKey(key)) {
          _logFirstDetectedTime[key] = timeStr;
        }
        final firstTime = _logFirstDetectedTime[key] ?? timeStr;
        _detectionLogs.add({...log, 'key': key, 'time': firstTime});
      }
    }

    // ─── LOG 1: Status Model (Kwon et al., 2013 — SAS-SV) ───────────────────
    // Trigger: _prediction == 1 (at risk/addicted berdasarkan SAS-SV)
    // Kwon hanya menghasilkan 2 label (0 = normal, 1 = at risk/addicted).
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
    // Landasan: Sert, Ünsal, Can (2026) — penggunaan sosmed ≥5 jam/hari
    // dikaitkan dengan skor adiksi lebih tinggi pada remaja SMA (n=858).
    if (_data.socialMediaUsage > 5.0) {
      addLog('sosmed_berlebihan', {
        'title': 'Penggunaan Sosial Media Berlebihan',
        'desc':
            'Penggunaan sosial media hari ini melebihi 5 jam. Remaja yang menggunakan sosial media ≥5 jam per hari menunjukkan skor adiksi smartphone yang lebih tinggi.',
        'color': const Color(0xFFEC4899),
        'icon': Icons.tag_rounded,
        'source': 'Sert, Ünsal, Can, 2026 — J Community Health. '
            'DOI: 10.1007/s10900-026-01578-7',
      });
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'sosmed_berlebihan');
    }

    // ─── LOG 3: Screen Time Tinggi ───────────────────────────────────────────
    // Trigger: dailyScreenTime > 4.0 jam/hari
    // Landasan: Francisquini et al. (2024) — screen time >4 jam/hari
    // dikaitkan dengan peningkatan gejala depresi, kecemasan, dan stres
    // pada remaja (n=1.627, Brazil).
    if (_data.dailyScreenTime > 4.0) {
      addLog('screen_time_tinggi', {
        'title': 'Screen Time Harian Tinggi',
        'desc':
            'Total waktu layar hari ini melebihi 4 jam. Penggunaan layar lebih dari 4 jam per hari berkaitan dengan peningkatan gejala depresi, kecemasan, dan stres pada remaja.',
        'color': const Color(0xFFF97316),
        'icon': Icons.phonelink_rounded,
        'source': 'Francisquini et al., 2024 — Revista Paulista de Pediatria. '
            'DOI: 10.1590/1984-0462/2025/43/2023250',
      });
    } else {
      _detectionLogs.removeWhere((l) => l['key'] == 'screen_time_tinggi');
    }

    // ─── LOG 4: Penggunaan Malam ─────────────────────────────────────────────
    // Trigger: nightUsage > 2.3 jam (di atas rata-rata durasi pakai HP
    // di tempat tidur pada remaja menurut Bozkurt et al., 2024)
    // Landasan: Bozkurt et al. (2024) — durasi penggunaan smartphone di
    // tempat tidur rata-rata 2,3 jam/hari; durasi lebih panjang berkaitan
    // positif dengan kualitas tidur buruk pada remaja usia 13–18 tahun.
    // nightUsage di sini = total durasi pakai HP antara 22:00–05:00
    // (proxy operasional untuk "penggunaan HP saat waktu tidur").
    if (_data.nightUsage > 2.3) {
      addLog('penggunaan_malam', {
        'title': 'Penggunaan Smartphone Malam Hari Tinggi',
        'desc':
            'Penggunaan smartphone antara pukul 22:00–05:00 melebihi 2,3 jam. Durasi penggunaan HP di waktu tidur yang melebihi rata-rata remaja berkaitan dengan kualitas tidur yang lebih buruk.',
        'color': const Color(0xFF6366F1),
        'icon': Icons.nightlight_rounded,
        'source': 'Bozkurt et al., 2024 — Eurasian Journal of Medicine. '
            'DOI: 10.5152/eurasianjmed.2024.23379',
      });
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

    debugPrint('🔑 hasPermission setelah resume: $_hasPermission');
    debugPrint('🔑 initialized: $_initialized');

    if (_hasPermission) {
      try {
        await fetchUsageData();
      } catch (e) {
        debugPrint('❌ fetchUsageData di resume gagal: $e');
      }
    }

    notifyListeners();
    debugPrint('🔔 notifyListeners dipanggil');
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
      Int64List? pattern;
      bool vibrate = true;
      if (_vibrationMode == 'off') {
        vibrate = false;
      } else if (_vibrationMode == 'pendek') {
        pattern = Int64List.fromList([0, 200, 100, 200]);
      } else if (_vibrationMode == 'panjang') {
        pattern = Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);
      }

      final channelId = 'jeda_alarm_${_alarmSound}_$_vibrationMode';

      await _notificationsPlugin.show(
        999,
        '⚠️ SAATNYA JEDA!',
        'Segera istirahat!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Alarm Jeda Keras',
            importance: Importance.max,
            priority: Priority.high,
            playSound: _isSoundEnabled,
            sound: _isSoundEnabled
                ? RawResourceAndroidNotificationSound(_alarmSound)
                : null,
            enableVibration: vibrate,
            vibrationPattern: vibrate ? pattern : null,
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
    _detectionLogs.clear();
    _data = UsageData();
    _logFirstDetectedTime.clear();
    _prediction = 0;
    _addictionProb = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_count', 0);
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
    } catch (e) {
      _appNamesLoaded = true;
      debugPrint('❌ Gagal load app names: $e');
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

  void _runPrediction() {
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

    _checkAndShowWarning();
  }

  void _checkAndShowWarning() async {
    if (_prediction != 1 || !_isMonitoringEnabled || _isWarningOpen) return;

    // Cek snooze dari native (JedaPrefs key: snoozeUntil, tipe Long/ms)
    // — bukan dari SharedPreferences Flutter, karena setSnooze disimpan
    // di sisi Kotlin via getSharedPreferences("JedaPrefs").
    try {
      final snoozeUntilMs =
          await platform.invokeMethod<int>('getSnoozeUntil') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < snoozeUntilMs) return;
    } catch (_) {
      // Jika native tidak support method ini, lanjut tanpa cek snooze
    }

    showNotificationAlert();

    _isWarningOpen = true;
    _showGlobalWarningDialog();
  }

  void _showGlobalWarningDialog() {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return;

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
                decoration: const BoxDecoration(
                    color: Color(0xFFF97316), shape: BoxShape.circle),
                child: const Icon(Icons.wb_sunny_rounded,
                    color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              Text('SAATNYA JEDA!',
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFF97316),
                      letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Text(
                getMotivationText(),
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
      if (_isMonitoringEnabled && _prediction == 1) {
        await enforceBlockIfNecessary();
        await showNotificationAlert();
        _checkAndShowWarning();
      }
    });
  }
}