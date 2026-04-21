import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
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
  bool _initialized = false;
  Timer? _midnightTimer;

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

  // ─────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────
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

    // ── Reset harian jam 00:00 ──
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastDate = prefs.getString('last_date');

    if (lastDate == todayStr) {
      // Hari sama → pakai notif tersimpan
      _data.notifications = prefs.getInt('notif_count') ?? 0;
    } else {
      // Hari baru → reset semua counter harian
      _data.notifications = 0;
      await prefs.setString('last_date', todayStr);
      await prefs.setInt('notif_count', 0);
      print('🔄 Reset harian: notifikasi, screen time, unlock → 0');
    }

    // Notifikasi dibaca lewat UsageStats di fetchUsageData()

    try {
      _hasPermission = (await UsageStats.checkUsagePermission()) ?? false;
    } catch (_) {
      _hasPermission = false;
    }

    if (_hasPermission) await fetchUsageData();

    _listenOverlayEvents();
    _scheduleMidnightReset();

    _isLoading = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // NOTIFICATION LISTENER
  // ─────────────────────────────────────────
  // NOTIFIKASI — baca dari UsageStats queryEvents
  // event type 6 = NOTIFICATION_INTERRUPTION
  // Lebih andal di Infinix karena pakai izin PACKAGE_USAGE_STATS
  // yang sudah terbukti jalan (screen time & unlock sudah OK)
  // ─────────────────────────────────────────
  Future<void> _fetchNotificationCount(SharedPreferences prefs) async {
    try {
      if (!_hasPermission) return;

      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);

      final allEvents = ((await UsageStats.queryEvents(startDate, now)) ?? [])
          .cast<EventUsageInfo>();

      // ── DEBUG: print semua event type yang ada hari ini ──
      final Map<int, int> typeCounts = {};
      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        typeCounts[et] = (typeCounts[et] ?? 0) + 1;
      }
      final sorted = typeCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      print('📋 Semua event type hari ini: ${sorted.map((e) => "type${e.key}=${e.value}x").join(", ")}');

      // Paket sistem yang diabaikan
      const ignored = {
        'android',
        'com.android.systemui',
        'com.android.phone',
        'com.android.settings',
        'com.wishnotregret.berijeda',
      };

      // Coba semua kemungkinan event type notifikasi:
      // 6  = NOTIFICATION_INTERRUPTION (Android stock)
      // 12 = bisa jadi notif di beberapa OEM
      // 19 = NOTIFICATION_SEEN di beberapa ROM
      // 20 = NOTIFICATION_INTERRUPTION di beberapa ROM
      const notifTypes = {6, 12, 19, 20};

      int count = 0;
      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        if (!notifTypes.contains(et)) continue;
        final pkg = e.packageName ?? '';
        if (pkg.isEmpty || ignored.contains(pkg)) continue;
        count++;
      }

      print('🔔 Notif count (type 6/12/19/20): $count');
      _data.notifications = count;
      await prefs.setInt('notif_count', count);
    } catch (e) {
      print('❌ Gagal fetch notif: $e');
    }
  }
  // ─────────────────────────────────────────
  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    final duration = nextMidnight.difference(now);

    print('⏰ Reset dijadwalkan dalam: ${duration.inHours}j ${duration.inMinutes % 60}m');

    _midnightTimer = Timer(duration, () async {
      print('🔄 RESET TENGAH MALAM — screen time, unlock, notifikasi → 0');
      final prefs = await SharedPreferences.getInstance();
      final now2 = DateTime.now();
      final todayStr = '${now2.year}-${now2.month}-${now2.day}';

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

      // Jadwalkan reset untuk tengah malam berikutnya
      _scheduleMidnightReset();
    });
  }

  // ─────────────────────────────────────────
  // FETCH USAGE DATA
  //
  // Screen Time  → dihitung manual dari pasangan event
  //   MOVE_TO_FOREGROUND (1) & MOVE_TO_BACKGROUND (2)
  //   per paket, lalu dijumlahkan SEMUA paket non-sistem
  //   → hasilnya = total durasi layar aktif dipakai user
  //   (mendekati "Screen Time" di Digital Wellbeing)
  //
  // Unlock Count → event SCREEN_INTERACTIVE (15) di Android ≥ 10
  //   atau USER_INTERACTION (23) sebagai fallback.
  //   Jika keduanya tidak ada, fallback ke KEYGUARD_HIDDEN (11).
  //
  // ─────────────────────────────────────────
  Future<void> fetchUsageData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);

      const socialPackages = {
        'com.instagram.android',
        'com.zhiliaoapp.musically',
        'com.ss.android.ugc.trill',
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

      // ── Paket sistem yang dieksklusi dari screen time ──
      // Ini mencegah launcher, system UI, dll menggelembungkan angka
      const systemPackagePrefixes = [
        'android',
        'com.android.',
        'com.google.android.inputmethod',
        'com.google.android.gms',
        'com.google.android.gsf',
        'com.google.android.packageinstaller',
        'com.infinix.',    // OEM Infinix
        'com.itel.',
        'com.transsion.',
      ];

      bool isSystemPackage(String pkg) {
        for (final prefix in systemPackagePrefixes) {
          if (pkg.startsWith(prefix)) return true;
        }
        return false;
      }

      // ════════════════════════════════════════
      // SCREEN TIME via FOREGROUND/BACKGROUND events
      // ════════════════════════════════════════
      //
      // Algoritma:
      //   Untuk setiap paket, kumpulkan semua event FOREGROUND & BACKGROUND
      //   yang diurutkan berdasarkan waktu. Setiap pasangan FG→BG
      //   menghasilkan durasi = BG.time - FG.time.
      //   Jika ada FG tanpa pasangan BG (app masih buka), gunakan `now`.
      //
      double totalScreenMs = 0;
      double socialMs = 0;
      double gamingMs = 0;

      // event type 1 = MOVE_TO_FOREGROUND, 2 = MOVE_TO_BACKGROUND
      final allEvents = ((await UsageStats.queryEvents(startDate, now)) ?? []).cast<EventUsageInfo>();

      // Kelompokkan per paket
      final Map<String, List<EventUsageInfo>> fgBgByPkg = {};
      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        if (et != 1 && et != 2) continue;
        final pkg = e.packageName ?? '';
        if (pkg.isEmpty || isSystemPackage(pkg)) continue;
        fgBgByPkg.putIfAbsent(pkg, () => <EventUsageInfo>[]).add(e);
      }

      for (final entry in fgBgByPkg.entries) {
        final pkg = entry.key;
        final events = entry.value
          ..sort((a, b) {
            final ta = int.tryParse(a.timeStamp?.toString() ?? '0') ?? 0;
            final tb = int.tryParse(b.timeStamp?.toString() ?? '0') ?? 0;
            return ta.compareTo(tb);
          });

        int? lastFgMs;
        for (final e in events) {
          final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
          final ts = int.tryParse(e.timeStamp?.toString() ?? '0') ?? 0;
          if (et == 1) {
            // FOREGROUND
            lastFgMs = ts;
          } else if (et == 2 && lastFgMs != null) {
            // BACKGROUND — hitung durasi
            final dur = ts - lastFgMs;
            if (dur > 0) {
              totalScreenMs += dur;
              if (socialPackages.contains(pkg)) socialMs += dur;
              if (gamePackages.contains(pkg)) gamingMs += dur;
            }
            lastFgMs = null;
          }
        }
        // App masih di foreground saat ini
        if (lastFgMs != null) {
          final dur = now.millisecondsSinceEpoch - lastFgMs;
          if (dur > 0) {
            totalScreenMs += dur;
            if (socialPackages.contains(pkg)) socialMs += dur;
            if (gamePackages.contains(pkg)) gamingMs += dur;
          }
        }
      }

      // ════════════════════════════════════════
      // UNLOCK COUNT
      // ════════════════════════════════════════
      //
      // Prioritas event type untuk unlock:
      //   15 = SCREEN_INTERACTIVE  (Android 10+, paling akurat)
      //   11 = KEYGUARD_HIDDEN     (layar tidak terkunci = unlock)
      //   Jika event 15 tersedia → pakai 15
      //   Jika tidak ada event 15 sama sekali → fallback ke 11
      //
      int unlockCount = 0;
      int countType15 = 0;
      int countType11 = 0;

      for (final e in allEvents) {
        final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
        if (et == 15) countType15++;
        if (et == 11) countType11++;
      }

      if (countType15 > 0) {
        // SCREEN_INTERACTIVE tersedia → paling akurat
        unlockCount = countType15;
        print('🔓 Unlock via SCREEN_INTERACTIVE (type 15): $unlockCount');
      } else if (countType11 > 0) {
        // Fallback ke KEYGUARD_HIDDEN
        unlockCount = countType11;
        print('🔓 Unlock via KEYGUARD_HIDDEN (type 11): $unlockCount');
      } else {
        // Last resort: KEYGUARD_SHOWN (12) — estimasi
        for (final e in allEvents) {
          final et = int.tryParse(e.eventType?.toString() ?? '') ?? -1;
          if (et == 12) unlockCount++;
        }
        print('🔓 Unlock via KEYGUARD_SHOWN fallback (type 12): $unlockCount');
      }

      // ════════════════════════════════════════
      // FINALIZE
      // ════════════════════════════════════════
      final screenHours = totalScreenMs / 3_600_000.0;
      final socialHours = socialMs / 3_600_000.0;
      final gamingHours = gamingMs / 3_600_000.0;

      print('📊 Screen time: ${screenHours.toStringAsFixed(2)} jam');
      print('📱 Social: ${socialHours.toStringAsFixed(2)} jam');
      print('🎮 Gaming: ${gamingHours.toStringAsFixed(2)} jam');

      _data = UsageData(
        dailyScreenTime: screenHours,
        appSessions: unlockCount,
        socialMediaUsage: socialHours,
        gamingTime: gamingHours,
        notifications: _data.notifications, // dipertahankan dari listener
        nightUsage: 0.0,
        appsInstalled: 0,
      );

      print('✅ Final → '
          'ST=${_data.dailyScreenTime.toStringAsFixed(2)}j '
          '| Unlock=$unlockCount '
          '| Notif=${_data.notifications}');

      // Ambil notifikasi dari UsageStats event type 6
      final prefs = await SharedPreferences.getInstance();
      await _fetchNotificationCount(prefs);

      _runPrediction();
    } catch (e, st) {
      print('❌ fetchUsageData error: $e\n$st');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // SETTINGS NAVIGATION
  // ─────────────────────────────────────────
  Future<void> openUsageSettings() async {
    await UsageStats.grantUsagePermission();
  }

  Future<void> openAccessibilitySettings() async {
    await platform.invokeMethod('openAccessibilitySettings');
  }

  // openNotificationSettings: tidak diperlukan lagi (pakai UsageStats)
  Future<void> openNotificationSettings() async {}

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

  // ─────────────────────────────────────────
  // OVERLAY & NATIVE
  // ─────────────────────────────────────────
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
      print('❌ Overlay listener: $e');
    }
  }

  Future<void> setMonitoring(bool value) async {
    _isMonitoringEnabled = value;
    notifyListeners();
    if (!value) {
      await _syncBlockerToNative(false);
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
      print('❌ Sync native: ${e.message}');
    }
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await platform.invokeMethod('checkAccessibilityEnabled');
    } catch (_) {
      return false;
    }
  }

  // Alias untuk kompatibilitas — gunakan openAccessibilitySettings()
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
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
    } on PlatformException catch (e) {
      print('❌ Snooze: ${e.message}');
    }
  }

  Future<void> enforceBlockIfNecessary() async {
    try {
      await platform.invokeMethod('enforceBlockIfNecessary');
    } catch (e) {
      print('❌ enforceBlock: $e');
    }
  }

  // ─────────────────────────────────────────
  // ALERTS
  // ─────────────────────────────────────────
  Future<void> showNotificationAlert() async {
    if (!_isMonitoringEnabled) return;
    try {
      await _notificationsPlugin.show(
        999,
        '⚠️ SAATNYA JEDA!',
        'Segera istirahat!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jeda_suara_final_v1',
            'Alarm Jeda Keras',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
        ),
      );
    } catch (e) {
      print('❌ Notif alert: $e');
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
      print('❌ Overlay: $e');
    }
  }

  // ─────────────────────────────────────────
  // DATA MANIPULATION
  // ─────────────────────────────────────────
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

  // ─────────────────────────────────────────
  // NAIVE BAYES
  // ─────────────────────────────────────────
  void _runPrediction() {
    if (_model != null) {
      final result = _model!.predict([
        _data.dailyScreenTime,
        _data.appSessions.toDouble(),
        _data.notifications.toDouble(),
      ]);
      _prediction = result['prediction'];
      _addictionProb = result['probability'];
    } else {
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