import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_provider.dart';
import '../widgets/jeda_alert_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = 'Pengguna';
  String? _userPhoto;
  bool _monitoringEnabled = true;
  Timer? _timer;
  DateTime _lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadUser();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AppProvider>();
      await provider.fetchUsageData();
      setState(() => _lastUpdated = DateTime.now());

      if (!_monitoringEnabled || !mounted) return;

      // Cek apakah monitoring dimatikan hari ini
      final prefs = await SharedPreferences.getInstance();
      final disabledToday = prefs.getBool('monitoring_disabled_today') ?? false;
      if (disabledToday) return;

      final snoozeUntil = prefs.getString('snooze_until');
      if (snoozeUntil != null) {
        final snoozeTime = DateTime.parse(snoozeUntil);
        if (DateTime.now().isBefore(snoozeTime)) return;
      }

      // 💡 TRIGEER ALARM OTOMATIS BERDASARKAN HASIL NAIVE BAYES
      if (provider.prediction == 1) {
        
        // PASANG PELACAK: Memunculkan teks di bawah layar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Memanggil Pembajak Layar dalam 3 detik...'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );

        // Delay 3 detik lalu tembak Overlay!
        Future.delayed(const Duration(seconds: 3), () async {
          await provider.showOverlayAlert();
        });
      }
    });

    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      await provider.fetchUsageData();
      setState(() => _lastUpdated = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Pengguna';
      _userPhoto = prefs.getString('user_photo');
    });
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

    final Color statusColor =
        status == 'AMAN' ? const Color(0xFF4CAF50) : const Color(0xFFEF4444);
    final String statusLabel =
        status == 'AMAN' ? 'Status Deteksi: AMAN' : 'Status Deteksi: BAHAYA';
    final String statusDesc = status == 'AMAN'
        ? 'Penggunaanmu masih wajar.\nPertahankan!'
        : 'Penggunaanmu sudah berlebihan.\nSaatnya istirahat!';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC107)))
          : RefreshIndicator(
              color: const Color(0xFFFFC107),
              onRefresh: () async {
                await provider.fetchUsageData();
                setState(() => _lastUpdated = DateTime.now());
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Header kuning
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFC107),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting(),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                'Halo, $_userName!',
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, '/edit-profile'),
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

                    // Last updated indicator
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
                              fontSize: 11,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Master Switch
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status Monitoring',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    Text(
                                      _monitoringEnabled
                                          ? 'Aktif - Mendeteksi'
                                          : 'Istirahat Mode',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: _monitoringEnabled
                                            ? const Color(0xFF4CAF50)
                                            : Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                                Switch(
                                  value: _monitoringEnabled,
                                  onChanged: (v) =>
                                      setState(() => _monitoringEnabled = v),
                                  activeColor: const Color(0xFFFFC107),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Status Card
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
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: _monitoringEnabled
                                ? Column(
                                    children: [
                                      Icon(Icons.wb_sunny_rounded,
                                          size: 64, color: statusColor),
                                      const SizedBox(height: 16),
                                      Text(
                                        statusLabel,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        statusDesc,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.grey[500],
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: prob,
                                          minHeight: 6,
                                          backgroundColor: Colors.grey[200],
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Akurasi Model: 98.23% | Probabilitas: ${(prob * 100).toStringAsFixed(1)}%',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Icon(Icons.wb_sunny_rounded,
                                          size: 64, color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Monitoring Mati',
                                        style: GoogleFonts.poppins(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 20),

                          // Grid Stats Penuh
                          Text(
                            'STATISTIK HARI INI',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[400],
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),

                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.6,
                            children: [
                              _statCard(
                                icon: Icons.hourglass_bottom_rounded,
                                iconColor: const Color(0xFFFFC107),
                                label: 'SCREEN TIME',
                                value: _formatHours(data.dailyScreenTime),
                              ),
                              _statCard(
                                icon: Icons.layers_rounded,
                                iconColor: const Color(0xFF6366F1),
                                label: 'SESI APLIKASI',
                                value: '${data.appSessions.toInt()}x',
                              ),
                              _statCard(
                                icon: Icons.tag_rounded,
                                iconColor: const Color(0xFFEC4899),
                                label: 'SOSIAL MEDIA',
                                value: _formatHours(data.socialMediaUsage),
                              ),
                              _statCard(
                                icon: Icons.sports_esports_rounded,
                                iconColor: const Color(0xFF10B981),
                                label: 'GAMING',
                                value: _formatHours(data.gamingTime),
                              ),
                              _statCard(
                                icon: Icons.notifications_rounded,
                                iconColor: const Color(0xFFF59E0B),
                                label: 'NOTIFIKASI',
                                value: '${data.notifications.toInt()}',
                              ),
                              _statCard(
                                icon: Icons.nightlight_round,
                                iconColor: const Color(0xFF6366F1),
                                label: 'SESI MALAM',
                                value: _formatHours(data.nightUsage),
                              ),
                              _statCard(
                                icon: Icons.grid_view_rounded,
                                iconColor: const Color(0xFFFFC107),
                                label: 'APP TERINSTALL',
                                value: '${data.appsInstalled.toInt()}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 💡 TOMBOL SENJATA RAHASIA DEMO SIDANG
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                // Eksekusi langsung tanpa nunggu proses otomatis!
                                await context.read<AppProvider>().showOverlayAlert();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A1A2E),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white),
                              label: Text(
                                'DEMO POP-UP JEDA',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
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

  Widget _statCard({required IconData icon, required Color iconColor, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const Spacer(),
          Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
          Text(label, style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400], letterSpacing: 0.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}