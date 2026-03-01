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

  @override
  void initState() {
    super.initState();
    _loadUser();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AppProvider>();
      await provider.fetchUsageData();
      if (provider.prediction == 1 && _monitoringEnabled && mounted) {
        JedaAlertDialog.show(context);
      }
    });
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
        status == 'AMAN' ? 'Kondisi AMAN' : 'Kondisi BAHAYA';
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
              onRefresh: () => provider.fetchUsageData(),
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
                            onTap: () =>
                                Navigator.pushNamed(context, '/profile'),
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
                                          : 'Istirahat / Produktif Mode',
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
                                      Icon(
                                        Icons.wb_sunny_rounded,
                                        size: 64,
                                        color: statusColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        statusLabel,
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
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: prob,
                                          minHeight: 6,
                                          backgroundColor: Colors.grey[200],
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(prob * 100).toStringAsFixed(1)}% probabilitas kecanduan',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Icon(
                                        Icons.wb_sunny_rounded,
                                        size: 64,
                                        color: Colors.grey[300],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Monitoring Mati',
                                        style: GoogleFonts.poppins(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Aktifkan switch di atas untuk memulai deteksi.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 20),

                          // Grid Stats
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

                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  icon: Icons.hourglass_bottom_rounded,
                                  iconColor: const Color(0xFFFFC107),
                                  label: 'SCREEN TIME',
                                  value: _formatHours(data.dailyScreenTime),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.lock_open_rounded,
                                  iconColor: const Color(0xFFFFC107),
                                  label: 'UNLOCK',
                                  value: '${data.appSessions}x',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  icon: Icons.nightlight_round,
                                  iconColor: const Color(0xFFFFC107),
                                  label: 'SESI MALAM',
                                  value: _formatHours(data.nightUsage),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Simulasi Deteksi Bahaya
                          GestureDetector(
                            onTap: () => JedaAlertDialog.show(context),
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.4),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Simulasi Deteksi Bahaya',
                                    style: GoogleFonts.poppins(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 9,
              color: Colors.grey[400],
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}