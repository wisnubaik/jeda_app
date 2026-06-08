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

// 💡 TAMBAHKAN WidgetsBindingObserver UNTUK SENSOR LAYAR AKTIF
class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  String _userName = 'Pengguna';
  String? _userPhoto;
  Timer? _timer;
  DateTime _lastUpdated = DateTime.now();
  AppProvider? _provider;
  bool _isWarningOpen = false;

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _loadUser();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    _provider = context.read<AppProvider>(); // tetap di sini
    await _provider!.initialize();
    
    if (mounted) setState(() => _lastUpdated = DateTime.now());

    bool isAccEnabled = await _provider!.isAccessibilityEnabled();
    if (!isAccEnabled && mounted) _showAccessibilityDialog();

    _checkAndShowWarning();
  });

  _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
    if (!mounted || _provider == null) return; // ← tambah null check
    await _provider!.fetchUsageData();
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  });
}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Matikan Sensor
    _timer?.cancel();
    super.dispose();
  }

  // 💡 SENSOR: KALAU APLIKASI DIBAWA KE DEPAN, LANGSUNG CEK!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndShowWarning();
    }
  }

  void _checkAndShowWarning() async {
    if (!mounted || _provider == null) return;
    
    if (_provider!.prediction == 1 && _provider!.isMonitoringEnabled && !_isWarningOpen) {
      final prefs = await SharedPreferences.getInstance();
      final snoozeStr = prefs.getString('snooze_until');
      if (snoozeStr != null) {
        final snoozeTime = DateTime.parse(snoozeStr);
        if (DateTime.now().isBefore(snoozeTime)) return; 
      }
      
      // 💡 DISINI TEMPATNYA: Bunyikan notif hanya saat pop-up mau muncul
      _provider!.showNotificationAlert(); 
      
      setState(() => _isWarningOpen = true);
      _showJedaWarningDialog();
    }
  }

  // 💡 FUNGSI TOMBOL SNOOZE (MURNI NATIVE KOTLIN)
  Future<void> _applySnooze(int seconds) async {
    _isWarningOpen = false;
    Navigator.pop(context); 
    
    // Titipkan angkanya ke Kotlin, lalu biarkan Kotlin yang bekerja!
    await _provider!.applySnoozeNative(seconds);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Jeda ditunda $seconds detik. Waktu dimulai!')),
      );
    }

    // 💣 TIMER: Saat waktu habis, cek apakah dia lagi main IG?
    Timer(Duration(seconds: seconds), () async {
      if (_provider != null && _provider!.isMonitoringEnabled && _provider!.prediction == 1) {
        
        // Panggil fungsi Kotlin yang baru kita buat
        await _provider!.enforceBlockIfNecessary();
        
        // Bunyikan notif
        _provider!.showNotificationAlert();

        if (mounted) {
          _checkAndShowWarning(); 
        }
      }
    });
  }

  void _showJedaWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Color(0xFFF97316), shape: BoxShape.circle),
                child: const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              Text('SAATNYA JEDA!', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFFF97316), letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Text('Pola penggunaanmu sudah\nberlebihan.\nMata dan pikiranmu butuh\nistirahat.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600], height: 1.5)),
              const SizedBox(height: 32),
              
              // TOMBOL 5 DETIK
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(5),
                  child: Text('Ingatkan 5 Detik Lagi', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),
              
              // TOMBOL 10 DETIK
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(10),
                  child: Text('Ingatkan 10 Detik Lagi', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),
              
              // TOMBOL 1 MENIT (60 Detik)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A2E), side: BorderSide(color: Colors.grey[300]!, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                  onPressed: () => _applySnooze(60),
                  child: Text('Ingatkan 1 Menit Lagi', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 28),
              
              GestureDetector(
                onTap: () async {
                  _isWarningOpen = false;
                  Navigator.pop(context);
                  await _provider!.setMonitoring(false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monitoring dimatikan hari ini.')));
                },
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
                    children: [
                      const TextSpan(text: 'Saya sedang produktif. '),
                      TextSpan(text: 'Matikan\nmonitoring hari ini!', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.grey[700], decoration: TextDecoration.underline)),
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

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.security, color: Color(0xFFEF4444)), SizedBox(width: 10), Text('Izin Diperlukan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        content: const Text('Aktifkan Layanan Aksesibilitas untuk aplikasi Jeda di Pengaturan HP Anda.', style: TextStyle(fontSize: 14)),
        actions: [TextButton(onPressed: () async { Navigator.pop(context); await context.read<AppProvider>().requestAccessibilityPermission(); }, child: const Text('BUKA PENGATURAN', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))))],
      ),
    );
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
    final isMonitoringEnabled = provider.isMonitoringEnabled;

    final Color statusColor = status == 'AMAN' ? const Color(0xFF4CAF50) : const Color(0xFFEF4444);
    final String statusLabel = status == 'AMAN' ? 'Status Deteksi: AMAN' : 'Status Deteksi: BAHAYA';
    final String statusDesc = status == 'AMAN' ? 'Penggunaanmu masih wajar.\nPertahankan!' : 'Penggunaanmu sudah berlebihan.\nSaatnya istirahat!';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      decoration: const BoxDecoration(color: Color(0xFFFFC107), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(), style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500, letterSpacing: 1)),
                              Text('Halo, $_userName!', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/edit-profile'),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white24,
                              backgroundImage: _userPhoto != null ? FileImage(File(_userPhoto!)) : null,
                              child: _userPhoto == null ? const Icon(Icons.person_rounded, color: Colors.white) : null,
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
                          Icon(Icons.sync_rounded, size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text('Diperbarui: ${_lastUpdated.hour.toString().padLeft(2, '0')}.${_lastUpdated.minute.toString().padLeft(2, '0')}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400])),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // Pastikan rata kiri
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Status Monitoring', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
                                    Text(isMonitoringEnabled ? 'Aktif - Mendeteksi' : 'Istirahat Mode', style: GoogleFonts.poppins(fontSize: 12, color: isMonitoringEnabled ? const Color(0xFF4CAF50) : Colors.grey[400])),
                                  ],
                                ),
                                Switch(value: isMonitoringEnabled, onChanged: (v) => provider.setMonitoring(v), activeColor: const Color(0xFFFFC107)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                            child: isMonitoringEnabled
                                ? Column(
                                    children: [
                                      Icon(Icons.wb_sunny_rounded, size: 64, color: statusColor),
                                      const SizedBox(height: 16),
                                      Text(statusLabel, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: statusColor)),
                                      const SizedBox(height: 8),
                                      Text(statusDesc, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500], height: 1.5)),
                                      const SizedBox(height: 16),
                                      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: prob, minHeight: 6, backgroundColor: Colors.grey[200], color: statusColor)),
                                      const SizedBox(height: 4),
                                      Text('Probabilitas: ${(prob * 100).toStringAsFixed(1)}%', 
    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400])),
                                    ],
                                  )
                                : Column(children: [Icon(Icons.wb_sunny_rounded, size: 64, color: Colors.grey[300]), const SizedBox(height: 16), Text('Monitoring Mati', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.grey[400]))]),
                          ),
                          const SizedBox(height: 30),
                          
                          // BAGIAN STATISTIK HARI INI
                          Text('STATISTIK HARI INI', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[400], letterSpacing: 1.5)),
                          const SizedBox(height: 16),
                          
                          // Menggunakan Column dan _buildWideStatCard untuk tampilan memanjang 3 baris
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

  // WIDGET BARU PENGGANTI _statCard LAMA
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
