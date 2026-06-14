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
  Map<String, double> _appUsageMap = {}; // variabel simpan data usage per app
  Map<String, String> _appNameMap =
      {}; // variabel simpan data nama app per package name
  Map<String, int> _appCategoryMap = {};
  Set<String> _launchablePackages = {};

  Map<String, double> get appUsageMap => _appUsageMap;
  Map<String, String> get appNameMap => _appNameMap;
  Map<String, int> get appCategoryMap => _appCategoryMap;
  Timer? _midnightTimer;
  Timer? _pollingTimer;

  // ⬇️ TAMBAH: state untuk dialog "SAATNYA JEDA!" global
  // (sebelumnya ada di DashboardScreen sebagai _isWarningOpen)
  bool _isWarningOpen = false;
  Timer? _snoozeTimer; // pengganti Timer lokal di _applySnooze dashboard

  // ── Preferensi personalisasi alarm "Saatnya Jeda" ──
  String _alarmSound = 'alarm'; // alarm | alarm_gentle | alarm_urgent
  String _vibrationMode = 'pendek'; // off | pendek | panjang
  int _motivationVariant = 0; // 0 = random, 1..N = pesan tertentu

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

  // Tambah di bagian deklarasi variabel atas AppProvider:
  final Map<String, String> _logFirstDetectedTime = {};

  final List<Map<String, dynamic>> _detectionLogs = [];
  List<Map<String, dynamic>> get detectionLogs => _detectionLogs;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.wishnotregret.berijeda/blocker');

  // Content-hash dedup: key = "pkg|title|body", value = timestamp terakhir
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

      const ignoredPkgs = {
        'android',
        'com.android.systemui',
        'com.android.phone',
        'com.wishnotregret.berijeda',
        'com.google.android.networkstack', // ←
        'com.google.android.packageinstaller', // ← sudah ada di systemPackagePrefixes tapi tambah aja lah bismillah
        'com.transsion.phonemaster', //
        'com.transsion.systemui', //
        'com.google.android.gms',
        'com.heytap.market',
        'com.coloros.weather.service',
      };

      // ← TAMBAH: hitung per package untuk debug
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

      // ← TAMBAH: print per package
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

      // Sanity check: savedCount tidak boleh jauh melebihi eventCount.
      // Jika savedCount > adjustedEventCount * 3, kemungkinan besar
      // savedCount adalah akumulasi multi-hari yang tidak ter-reset
      // (timer midnight mati karena app di-kill).
      // Dalam kasus ini, percayai eventCount sebagai baseline.
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

    await _loadAppNames();
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

        final hasRemoved = event.hasRemoved ?? false;
        if (hasRemoved) return;

        // ── Filter summary notif WhatsApp/Telegram (tanpa groupKey) ──
// v0.3.5 tidak expose groupKey, jadi deteksi dari pola title.
// Summary notif biasanya: "5 pesan baru", "3 messages", "(2)", dll.
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

        // ── Content-hash dedup (ganti cooldown 500ms) ──
        // Hash = pkg + title + body. Notif SAMA persis dalam 1 detik → skip.
        // Notif BERBEDA konten (pesan berbeda) dalam 1 detik → tetap dihitung.
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

  // ── Hapus channel notifikasi lama agar kombinasi suara+getaran baru terpakai ──
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

  // Di _scheduleMidnightReset(), sudah ada _notifHashTime.clear() ✅
// Tambahan: cleanup entry lama setiap 30 menit agar tidak menumpuk
// jika app jalan lama tanpa restart
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
      _cleanupNotifHashMap(); // ← tambahkan ini
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

      // Untuk menangkap sesi lintas tengah malam, query dari 4 jam sebelum
      // midnight kemarin (20:00 kemarin). Ini cukup untuk menangkap sesi
      // malam yang paling larut sekalipun, tanpa mengambil data terlalu jauh.
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

      // isSystemPackage: app dianggap "sistem" jika tidak ada di
      // _launchablePackages (tidak punya launcher icon).
      // Daftar ini diisi dari native saat _loadAppNames() dipanggil,
      // dengan filter Intent.CATEGORY_LAUNCHER — tidak perlu hardcode.
      bool isSystemPackage(String pkg) {
        return !_launchablePackages.contains(pkg);
      }

      // Query event dari windowStart (kemarin 20:00) sampai sekarang.
      // queryEvents mengembalikan event individual bertimestamp — AMAN dari
      // bug ROM OPPO yang hanya menyerang queryUsageStats (akumulasi).
      final allEvents = ((await UsageStats.queryEvents(windowStart, now)) ?? [])
          .cast<EventUsageInfo>()
          .toList();

      // ════ STEP 1: Screen-off timestamps & unlock count (hari ini saja) ════
      final List<int> screenOffTimestamps = [];
      int screenUnlockCount = 0;
      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        final pkg = e.packageName ?? '';
        if (pkg != 'android') continue;
        final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
        if (et == 2 || et == 15) {
          // screen-off: hitung semua dalam window (termasuk kemarin malam)
          screenOffTimestamps.add(tsMs);
        }
        if (et == 18 && tsMs >= startOfDayMs) {
          // unlock: hanya hitung yang terjadi hari ini
          screenUnlockCount++;
        }
      }
      debugPrint('🔓 Screen unlocks: $screenUnlockCount');

      // ════ STEP 2: Event-based duration ════
      //
      // Dua kategori sesi yang dihitung untuk hari ini:
      //
      // A) Sesi murni hari ini: FOREGROUND >= startOfDayMs
      //    Dihitung seperti biasa.
      //
      // B) Sesi lintas tengah malam: FOREGROUND kemarin (dalam window 20:00-
      //    23:59), BACKGROUND >= startOfDayMs (setelah midnight)
      //    Hanya durasi yang jatuh SETELAH midnight yang dihitung untuk hari ini.
      //    Syarat ketat: tidak boleh ada screen-off antara FOREGROUND dan
      //    BACKGROUND — jika ada, sesi terputus dan tidak dihitung.
      //
      // Event 23 (ACTIVITY_RESUMED) tetap dibuang — hanya type 1 dan 2.

      final Map<String, int> foregroundStart = {}; // pkg → timestamp FOREGROUND
      final Map<String, double> eventsDuration = {}; // durasi hari ini per app

      // appsWithActivityToday: app yang benar-benar punya FOREGROUND atau
      // sesi lintas midnight yang valid HARI INI. Dipakai untuk filter
      // _appUsageMap agar app yang tidak aktif hari ini tidak muncul.
      final Set<String> appsWithActivityToday = {};

      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        final pkg = e.packageName ?? '';
        if (pkg.isEmpty || isSystemPackage(pkg)) continue;
        if (et != 1 && et != 2) continue;

        final tsMs = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;

        if (et == 1) {
          // FOREGROUND: catat timestamp (bisa dari kemarin maupun hari ini)
          foregroundStart[pkg] = tsMs;
        } else if (et == 2) {
          // BACKGROUND
          final startMs = foregroundStart[pkg];
          if (startMs == null)
            continue; // tidak ada FOREGROUND sebelumnya → skip

          if (startMs >= startOfDayMs) {
            // ── Kasus A: Sesi murni hari ini ──
            // FOREGROUND dan BACKGROUND keduanya hari ini.
            final duration = tsMs - startMs;
            if (duration > 0 && duration <= 7200000) {
              eventsDuration[pkg] = (eventsDuration[pkg] ?? 0) + duration;
              appsWithActivityToday.add(pkg);
            }
          } else if (tsMs >= startOfDayMs) {
            // ── Kasus B: Sesi lintas tengah malam ──
            // FOREGROUND kemarin (dalam window), BACKGROUND hari ini.
            //
            // Validasi: tidak boleh ada screen-off antara FOREGROUND dan
            // BACKGROUND. Jika ada screen-off, berarti HP mati di tengah sesi
            // → sesi terputus → hanya hitung sampai screen-off pertama.
            final screenOffBetween = screenOffTimestamps
                .where((t) => t > startMs && t < tsMs)
                .toList()
              ..sort();

            final int effectiveEnd;
            if (screenOffBetween.isNotEmpty) {
              // Ada screen-off → sesi berakhir saat screen-off pertama.
              // Hanya hitung bagian setelah midnight sampai screen-off pertama.
              // Jika screen-off sebelum midnight, tidak ada durasi hari ini.
              effectiveEnd = screenOffBetween.first;
            } else {
              // Tidak ada screen-off → sesi tidak terputus, hitung penuh.
              effectiveEnd = tsMs;
            }

            // Bagian yang jatuh setelah midnight = effectiveEnd - startOfDayMs
            if (effectiveEnd > startOfDayMs) {
              final durationToday = effectiveEnd - startOfDayMs;
              // Batas wajar: sesi lintas midnight tidak boleh > 4 jam hari ini
              // (jika user tidur sambil buka app, biasanya tidak lama)
              if (durationToday > 0 && durationToday <= 14400000) {
                eventsDuration[pkg] =
                    (eventsDuration[pkg] ?? 0) + durationToday;
                appsWithActivityToday.add(pkg);
                debugPrint(
                    '🌙 Split midnight: $pkg +${(durationToday / 60000).toStringAsFixed(1)}m');
              }
            }
          }
          // BACKGROUND < startOfDayMs: sesi selesai kemarin → tidak dihitung.
          foregroundStart.remove(pkg);
        }
      }

      // ════ STEP 3: Sesi aktif (FOREGROUND tanpa BACKGROUND) ════
      //
      // Syarat ketat agar tidak phantom:
      // (a) Tidak ada screen-off setelah FOREGROUND dimulai.
      // (b) Jika FOREGROUND dari kemarin (lintas midnight): durasi hari ini
      //     dihitung dari startOfDayMs sampai sekarang, max 30 menit.
      // (c) Jika FOREGROUND hari ini: durasi dari FOREGROUND sampai sekarang,
      //     max 30 menit.
      foregroundStart.forEach((pkg, startMs) {
        // Cek screen-off setelah FOREGROUND dimulai
        final hasScreenOffAfterStart =
            screenOffTimestamps.any((t) => t > startMs);
        if (hasScreenOffAfterStart) return; // layar sudah mati → skip

        final int effectiveStart =
            startMs < startOfDayMs ? startOfDayMs : startMs;
        final duration = nowMs - effectiveStart;

        // Max 30 menit untuk sesi aktif (heuristik anti-phantom)
        if (duration > 0 && duration <= 1800000) {
          eventsDuration[pkg] =
              (eventsDuration[pkg] ?? 0) + duration.toDouble();
          appsWithActivityToday.add(pkg);
        }
      });

      // Debug
      eventsDuration.forEach((pkg, ms) {
        debugPrint('  📱 events: ${(ms / 3600000).toStringAsFixed(2)}j │ $pkg');
      });

      // ════ STEP 4: queryUsageStats — referensi debug saja ════
      //
      // Tidak dipakai untuk rekonsiliasi. ROM OPPO/ColorOS terkonfirmasi
      // mengembalikan data akumulasi multi-hari dari queryUsageStats, sehingga
      // tidak bisa dipercaya untuk menentukan apakah app dipakai hari ini.
      // queryEvents (dipakai di atas) tidak memiliki bug ini karena
      // mengembalikan event individual bertimestamp, bukan akumulasi.
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

      // ════ STEP 5: Rekonsiliasi ════
      // Sumber tunggal: eventsDuration, hanya app di appsWithActivityToday.
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

      // Update _appUsageMap
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

      // ════ NIGHT USAGE ════
      // Night usage dihitung dari window penuh (termasuk kemarin malam)
      // karena periode malam melintasi midnight.
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
        // Validasi: jika ada screen-off setelah FOREGROUND dimulai,
        // gunakan screen-off pertama sebagai batas akhir sesi,
        // bukan 'now'. Ini mencegah phantom sesi dari kemarin 20:00
        // terhitung sampai sekarang (bisa 7+ jam).
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

    // Jangan duplikat — cek dulu apakah log sejenis sudah ada
    void addLog(String key, Map<String, dynamic> log) {
      final exists = _detectionLogs.any((l) => l['key'] == key);
      if (!exists) {
        // Catat waktu PERTAMA kali kondisi ini terpenuhi
        if (!_logFirstDetectedTime.containsKey(key)) {
          _logFirstDetectedTime[key] = timeStr;
        }
        final firstTime = _logFirstDetectedTime[key] ?? timeStr;
        _detectionLogs.add({...log, 'key': key, 'time': firstTime});
      }
    }

    // 1. Status model
    if (_prediction == 2) {
      addLog('status_bahaya', {
        'title': 'Status: BAHAYA',
        'desc':
            'Model deteksi menunjukkan pola penggunaan berisiko tinggi berdasarkan durasi, sesi, dan notifikasi harian.',
        'color': const Color(0xFFEF4444),
        'icon': Icons.warning_rounded,
        'source': 'Kwon et al., 2013 — SAS-SV',
      });
      _detectionLogs.removeWhere((l) => l['key'] == 'status_waspada');
    } else if (_prediction == 1) {
      addLog('status_waspada', {
        'title': 'Status: WASPADA',
        'desc':
            'Penggunaan mendekati batas risiko. Kurangi durasi layar sebelum meningkat ke kategori bahaya.',
        'color': const Color(0xFFFFC107),
        'icon': Icons.info_rounded,
        'source': 'Kwon et al., 2013 — SAS-SV',
      });
      _detectionLogs.removeWhere((l) => l['key'] == 'status_bahaya');
    } else {
      // Kembali aman — hapus status
      _detectionLogs.removeWhere(
          (l) => l['key'] == 'status_bahaya' || l['key'] == 'status_waspada');
    }

    // 2. Dominasi sosial media
    if (_data.dailyScreenTime > 0 &&
        (_data.socialMediaUsage / _data.dailyScreenTime) > 0.5) {
      addLog('dominasi_sosmed', {
        'title': 'Dominasi Sosial Media',
        'desc':
            'Lebih dari 50% waktu layarmu digunakan untuk sosial media. Remaja yang menggunakan sosmed >3 jam/hari berisiko lebih tinggi mengalami depresi dan kecemasan.',
        'color': const Color(0xFFEC4899),
        'icon': Icons.tag_rounded,
        'source': 'Springer Nature, 2025',
      });
    }

    // 3. Penggunaan malam
    if (_data.nightUsage > 0.5) {
      _detectionLogs.removeWhere((l) => l['key'] == 'aktivitas_malam');
      addLog('malam_berlebihan', {
        'title': 'Penggunaan Malam Berlebihan',
        'desc':
            'Terdeteksi penggunaan smartphone >30 menit setelah pukul 22:00. Berkaitan dengan gangguan tidur dan penurunan kesehatan mental remaja.',
        'color': const Color(0xFF6366F1),
        'icon': Icons.nightlight_rounded,
        'source':
            'Swedish Public Health Agency, 2024; Journal of Adolescence, 2024',
      });
    } else if (_data.nightUsage > 0.0) {
      _detectionLogs.removeWhere((l) => l['key'] == 'malam_berlebihan');
      addLog('aktivitas_malam', {
        'title': 'Aktivitas Malam Terdeteksi',
        'desc':
            'Terdeteksi penggunaan smartphone setelah pukul 22:00. Hindari layar minimal 1 jam sebelum tidur.',
        'color': const Color(0xFF8B5CF6),
        'icon': Icons.nightlight_outlined,
        'source': 'Swedish Public Health Agency, 2024',
      });
    }

    // 4. Sosial media di malam hari
    if (_data.nightUsage > 0.3 && _data.socialMediaUsage > 1.0) {
      addLog('sosmed_malam', {
        'title': 'Sosial Media di Malam Hari',
        'desc':
            'Kombinasi penggunaan sosmed tinggi dan aktif di malam hari secara khusus berkaitan dengan gangguan tidur dan depresi pada remaja di 18 negara.',
        'color': const Color(0xFFF97316),
        'icon': Icons.bedtime_rounded,
        'source': 'Sleep Health Journal, 2023',
      });
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

    debugPrint(
        '🔑 hasPermission setelah resume: $_hasPermission'); // ← sudah ada
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
      Int64List? pattern;
      bool vibrate = true;
      if (_vibrationMode == 'off') {
        vibrate = false;
      } else if (_vibrationMode == 'pendek') {
        pattern = Int64List.fromList([0, 200, 100, 200]);
      } else if (_vibrationMode == 'panjang') {
        pattern = Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);
      }

      // Channel ID unik per kombinasi suara+getaran karena setting
      // channel Android bersifat immutable setelah dibuat.
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
      // _launchablePackages diisi dari hasil filter native (hanya app
      // yang punya launcher icon). isSystemPackage() pakai ini sebagai
      // satu-satunya sumber kebenaran — tidak perlu daftar hardcode lagi.
      _launchablePackages = {
        for (final app in apps) (app['packageName'] as String)
      };
      // Selalu exclude app Jeda sendiri dari perhitungan screen time
      _launchablePackages.remove('com.wishnotregret.berijeda');
      _appNamesLoaded = true;
      debugPrint('✅ App names loaded: ${_appNameMap.length} apps');
    } catch (e) {
      _appNamesLoaded = true;
      debugPrint('❌ Gagal load app names: $e');
    }
  }

  String _getAppName(String pkg) {
    return _appNameMap[pkg] ?? pkg.split('.').last;
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
        _data.dailyScreenTime, // features[0]: screen_time (jam)
        _data.appSessions.toDouble(), // features[1]: unlocks (kali)
        _data.notifications.toDouble(), // features[2]: notif (kali)
      ]);
      _prediction = result['prediction'];
      _addictionProb = result['probability'];
      _generateDetectionLogs();

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

    // ⬇️ TAMBAH: setiap kali prediksi selesai dihitung, cek apakah
    // perlu menampilkan dialog "SAATNYA JEDA!" — dialog ini sekarang
    // global (bisa muncul di halaman manapun, bukan cuma Dashboard).
    _checkAndShowWarning();
  }

  // ════════════════════════════════════════════════════════
  // ⬇️ TAMBAH: BAGIAN DIALOG GLOBAL "SAATNYA JEDA!"
  // Dipindah dari DashboardScreen agar bisa muncul di semua halaman.
  // ════════════════════════════════════════════════════════

  // Cek apakah dialog perlu ditampilkan, dengan cek snooze dulu.
  void _checkAndShowWarning() async {
    if (_prediction != 1 || !_isMonitoringEnabled || _isWarningOpen) return;

    final prefs = await SharedPreferences.getInstance();
    final snoozeStr = prefs.getString('snooze_until');
    if (snoozeStr != null) {
      final snoozeTime = DateTime.parse(snoozeStr);
      if (DateTime.now().isBefore(snoozeTime)) return;
    }

    // Bunyikan notif alarm bersamaan dengan pop-up
    showNotificationAlert();

    _isWarningOpen = true;
    _showGlobalWarningDialog();
  }

  // Tampilkan dialog "SAATNYA JEDA!" menggunakan navigatorKey global,
  // sehingga muncul di atas halaman apapun yang sedang aktif.
  void _showGlobalWarningDialog() {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return; // navigator belum siap, batalkan

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
                getMotivationText(), // pesan motivasi acak/sesuai pilihan user
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 32),

              // TOMBOL 5 DETIK
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
                  onPressed: () => _applySnooze(dialogContext, 5),
                  child: Text('Ingatkan 5 Detik Lagi',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),

              // TOMBOL 10 DETIK
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

              // TOMBOL 1 MENIT
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A2E),
                      side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(dialogContext, 60),
                  child: Text('Ingatkan 1 Menit Lagi',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 28),

              // MATIKAN MONITORING HARI INI
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

  // Logic snooze — dipindah dari _applySnooze di DashboardScreen.
  // Sekarang menerima dialogContext (bukan context dashboard) agar
  // Navigator.pop menutup DIALOG, bukan halaman.
  Future<void> _applySnooze(BuildContext dialogContext, int seconds) async {
    _isWarningOpen = false;

    // Ambil ScaffoldMessenger SEBELUM pop (sesuai fix sebelumnya),
    // dari navigatorKey context (selalu hidup), bukan dialogContext.
    final ctx = navigatorKey.currentState?.context;
    final messenger = ctx != null ? ScaffoldMessenger.of(ctx) : null;

    Navigator.pop(dialogContext); // tutup dialog

    await applySnoozeNative(seconds);

    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Jeda ditunda $seconds detik. Waktu dimulai!')),
      );
    }

    // Timer: saat snooze habis, cek ulang apakah masih dalam kondisi bahaya
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