import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  String _userName = 'Pengguna';
  String? _userPhoto;
  Timer? _timer;
  DateTime _lastUpdated = DateTime.now();
  AppProvider? _provider;
  bool _accDialogOpen = false;
  // ⬇️ DIHAPUS: _isWarningOpen — sekarang dikelola AppProvider

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _provider = context.read<AppProvider>();
      await _provider!.initialize();

      if (mounted) setState(() => _lastUpdated = DateTime.now());

      bool isAccEnabled = await _provider!.isAccessibilityEnabled();
      if (!isAccEnabled && mounted) _showAccessibilityDialog();
      // ⬇️ DIHAPUS: _checkAndShowWarning() — sekarang dipanggil otomatis
      // oleh AppProvider setiap kali _runPrediction() selesai.
    });

    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _provider == null) return;
      await _provider!.fetchUsageData();
      if (mounted) setState(() => _lastUpdated = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // 💡 SENSOR: KALAU APLIKASI DIBAWA KE DEPAN, LANGSUNG CEK!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibility();
      // Sinkronkan status monitoring dari native: jika monitoring dimatikan
      // via overlay saat app di background, toggle dashboard ikut OFF.
      context.read<AppProvider>().onAppResumed();
    }
  }

  // ⬇️ DIHAPUS SELURUHNYA:
  // - _checkAndShowWarning()
  // - _applySnooze()
  // - _showJedaWarningDialog()
  // Semua sudah dipindah ke AppProvider sebagai dialog global
  // (lihat _checkAndShowWarning, _showGlobalWarningDialog, _applySnooze
  // di app_provider.dart).

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.shield_outlined, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Expanded(
            child: Text('Aktifkan Fitur Pemblokiran',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          )
        ]),
        content: const Text(
            'Fitur pemblokiran membantu menahan penggunaan aplikasi saat '
            'terdeteksi berlebihan. Untuk mengaktifkannya, Jeda memerlukan '
            'izin Layanan Aksesibilitas dan izin tampil di atas aplikasi lain.\n\n'
            'Fitur ini bersifat opsional — Jeda tetap dapat memantau '
            'penggunaan meski izin ini tidak diaktifkan.',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('NANTI SAJA',
                  style: TextStyle(color: Color(0xFF6B7280)))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final provider = context.read<AppProvider>();
                // Minta izin overlay dulu (opsional), lalu accessibility.
                // Keduanya untuk fitur pemblokiran yang sama.
                try {
                  final overlayGranted =
                      await provider.isOverlayPermissionGranted();
                  if (!overlayGranted) {
                    await provider.requestOverlayPermission();
                  }
                } catch (_) {}
                await provider.requestAccessibilityPermission();
              },
              child: const Text('AKTIFKAN',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))))
        ],
      ),
    ).then((_) => _accDialogOpen = false);
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Pengguna';
      _userPhoto = prefs.getString('user_photo');
    });
  }

  Future<void> _checkAccessibility() async {
    if (_accDialogOpen || _provider == null) return;
    final enabled = await _provider!.isAccessibilityEnabled();
    if (!enabled && mounted) {
      _showAccessibilityDialog();
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'SELAMAT PAGI,';
    if (hour < 15) return 'SELAMAT SIANG,';
    if (hour < 18) return 'SELAMAT SORE,';
    return 'SELAMAT MALAM,';
  }

  String _formatHours(double h) {
    int hours = h.toInt();
    int minutes = ((h - hours) * 60).toInt();
    if (hours > 0 && minutes > 0) return '${hours}j ${minutes}m';
    if (hours > 0) return '${hours}j';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final data = provider.data;
    final status = provider.status;
    final prob = provider.addictionProb;
    final isMonitoringEnabled = provider.isMonitoringEnabled;

    final Color statusColor =
        status == 'AMAN' ? const Color(0xFF4CAF50) : const Color(0xFFEF4444);
    final String statusLabel =
        status == 'AMAN' ? 'Status Deteksi: AMAN' : 'Status Deteksi: BAHAYA';
    final String statusDesc = status == 'AMAN'
        ? 'Penggunaanmu masih wajar.\nPertahankan!'
        : 'Penggunaanmu sudah berlebihan.\nSaatnya istirahat!';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: provider.isInitialLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC107)))
          : RefreshIndicator(
              color: const Color(0xFFFFC107),
              onRefresh: () async {
                await provider.fetchUsageData();
                if (mounted) setState(() => _lastUpdated = DateTime.now());
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      decoration: const BoxDecoration(
                          color: Color(0xFFFFC107),
                          borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(28),
                              bottomRight: Radius.circular(28))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ⬇️ GANTI: Column dibungkus Expanded + ellipsis
                          // (fix nama panjang, dari diskusi sebelumnya)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_greeting(),
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 1)),
                                Text(
                                  'Halo, $_userName!',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () =>
                                Navigator.pushNamed(context, '/edit-profile'),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white24,
                              backgroundImage: _userPhoto != null
                                  ? FileImage(File(_userPhoto!))
                                  : null,
                              child: _userPhoto == null
                                  ? const Icon(Icons.person_rounded,
                                      color: Colors.white)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.sync_rounded,
                              size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                              'Diperbarui: ${_lastUpdated.hour.toString().padLeft(2, '0')}.${_lastUpdated.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.grey[400])),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8)
                                ]),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Status Monitoring',
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF1A1A2E))),
                                    Text(
                                        isMonitoringEnabled
                                            ? 'Aktif - Mendeteksi'
                                            : 'Istirahat Mode',
                                        style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: isMonitoringEnabled
                                                ? const Color(0xFF4CAF50)
                                                : Colors.grey[400])),
                                  ],
                                ),
                                Switch(
                                    value: isMonitoringEnabled,
                                    onChanged: (v) => provider.setMonitoring(v),
                                    activeColor: const Color(0xFFFFC107)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 32, horizontal: 24),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8)
                                ]),
                            child: isMonitoringEnabled
                                ? Column(
                                    children: [
                                      Icon(Icons.wb_sunny_rounded,
                                          size: 64, color: statusColor),
                                      const SizedBox(height: 16),
                                      Text(statusLabel,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: statusColor)),
                                      const SizedBox(height: 8),
                                      Text(statusDesc,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: Colors.grey[500],
                                              height: 1.5)),
                                      const SizedBox(height: 16),
                                      ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                              value: prob,
                                              minHeight: 6,
                                              backgroundColor: Colors.grey[200],
                                              color: statusColor)),
                                      const SizedBox(height: 4),
                                      Text(
                                          'Probabilitas: ${(prob * 100).toStringAsFixed(1)}%',
                                          style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: Colors.grey[400])),
                                    ],
                                  )
                                : Column(children: [
                                    Icon(Icons.wb_sunny_rounded,
                                        size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 16),
                                    Text('Monitoring Mati',
                                        style: GoogleFonts.poppins(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey[400]))
                                  ]),
                          ),
                          const SizedBox(height: 30),
                          Text('STATISTIK HARI INI',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[400],
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 16),
                          Column(
                            children: [
                              _buildWideStatCard(
                                icon: Icons.hourglass_bottom_rounded,
                                iconColor: const Color(0xFFFFC107),
                                label: 'SCREEN TIME',
                                value: _formatHours(data.dailyScreenTime),
                              ),
                              _buildWideStatCard(
                                icon: Icons.lock_open_rounded,
                                iconColor: const Color(0xFF6366F1),
                                label: 'FREKUENSI DIBUKA',
                                value: '${data.appSessions.toInt()}x',
                              ),
                              _buildWideStatCard(
                                icon: Icons.notifications_active_rounded,
                                iconColor: const Color(0xFFEC4899),
                                label: 'TOTAL NOTIFIKASI',
                                value: '${data.notifications.toInt()}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWideStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}