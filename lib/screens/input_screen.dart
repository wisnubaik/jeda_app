import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/app_provider.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _screenTimeCtrl = TextEditingController();
  final _appSessionsCtrl = TextEditingController();
  final _socialMediaCtrl = TextEditingController();
  final _gamingCtrl = TextEditingController();
  final _notifCtrl = TextEditingController();
  final _nightUsageCtrl = TextEditingController();
  final _appsInstalledCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = context.read<AppProvider>().data;
    _screenTimeCtrl.text = data.dailyScreenTime.toString();
    _appSessionsCtrl.text = data.appSessions.toString();
    _socialMediaCtrl.text = data.socialMediaUsage.toString();
    _gamingCtrl.text = data.gamingTime.toString();
    _notifCtrl.text = data.notifications.toString();
    _nightUsageCtrl.text = data.nightUsage.toString();
    _appsInstalledCtrl.text = data.appsInstalled.toString();
  }

  @override
  void dispose() {
    _screenTimeCtrl.dispose();
    _appSessionsCtrl.dispose();
    _socialMediaCtrl.dispose();
    _gamingCtrl.dispose();
    _notifCtrl.dispose();
    _nightUsageCtrl.dispose();
    _appsInstalledCtrl.dispose();
    super.dispose();
  }

  void _save() {
    context.read<AppProvider>().updateData(
          screenTime: double.tryParse(_screenTimeCtrl.text) ?? 0,
          appSessions: int.tryParse(_appSessionsCtrl.text) ?? 0,
          socialMedia: double.tryParse(_socialMediaCtrl.text) ?? 0,
          gaming: double.tryParse(_gamingCtrl.text) ?? 0,
          notifications: int.tryParse(_notifCtrl.text) ?? 0,
          nightUsage: double.tryParse(_nightUsageCtrl.text) ?? 0,
          appsInstalled: int.tryParse(_appsInstalledCtrl.text) ?? 0,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Update Data Penggunaan',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A2E)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildField(
              controller: _screenTimeCtrl,
              label: 'Screen Time Harian',
              unit: 'jam',
              icon: Icons.access_time_rounded,
              color: const Color(0xFF6366F1),
            ),
            _buildField(
              controller: _appSessionsCtrl,
              label: 'Jumlah Sesi Aplikasi',
              unit: 'sesi',
              icon: Icons.layers_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            _buildField(
              controller: _socialMediaCtrl,
              label: 'Penggunaan Sosial Media',
              unit: 'jam',
              icon: Icons.tag_rounded,
              color: const Color(0xFFEC4899),
            ),
            _buildField(
              controller: _gamingCtrl,
              label: 'Waktu Gaming',
              unit: 'jam',
              icon: Icons.sports_esports_rounded,
              color: const Color(0xFF10B981),
            ),
            _buildField(
              controller: _notifCtrl,
              label: 'Jumlah Notifikasi',
              unit: 'notif',
              icon: Icons.notifications_rounded,
              color: const Color(0xFFF59E0B),
            ),
            _buildField(
              controller: _nightUsageCtrl,
              label: 'Penggunaan Malam Hari',
              unit: 'jam',
              icon: Icons.nightlight_round,
              color: const Color(0xFF6366F1),
            ),
            _buildField(
              controller: _appsInstalledCtrl,
              label: 'Aplikasi Terinstall',
              unit: 'app',
              icon: Icons.grid_view_rounded,
              color: const Color(0xFF06B6D4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Simpan & Deteksi',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.poppins(fontSize: 15),
            decoration: InputDecoration(
              suffixText: unit,
              suffixStyle: GoogleFonts.poppins(
                color: Colors.grey[400],
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}