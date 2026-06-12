import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:jeda_app/services/app_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = 'Nama User';
  String _userClass = 'Kelas 7';
  String _userMotivation = '';
  String? _userPhoto;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  /// Ubah "budi   santoso" -> "Budi Santoso"
  String _toTitleCase(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final raw = prefs.getString('user_name') ?? 'Nama User';
      _userName = raw.isNotEmpty ? _toTitleCase(raw) : 'Nama User';
      _userClass = prefs.getString('user_class') ?? 'Kelas 7';
      _userMotivation = prefs.getString('user_motivation') ?? '';
      _userPhoto = prefs.getString('user_photo');
    });
  }

  Future<void> _resetData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Column(
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 40),
            const SizedBox(height: 8),
            Text(
              'Reset Data Hari Ini?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Semua riwayat durasi dan deteksi hari ini akan dihapus dari perhitungan. Tindakan ini tidak dapat dibatalkan.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Batal',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Ya, Reset',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      final provider = context.read<AppProvider>();
      await provider.resetDailyData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Data harian berhasil direset!',
                style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFFFFC107),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
              decoration: const BoxDecoration(
                color: Color(0xFFFFC107),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.white24,
                    backgroundImage: _userPhoto != null
                        ? FileImage(File(_userPhoto!))
                        : null,
                    child: _userPhoto == null
                        ? const Icon(Icons.person_rounded,
                            color: Colors.white, size: 44)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  // STEP: Nama dibungkus Padding horizontal + dibatasi
                  // 1 baris dengan TextOverflow.ellipsis, agar nama
                  // panjang otomatis dipotong jadi "..." dan tidak
                  // merusak layout header (adaptif ke lebar device,
                  // tidak perlu hardcode jumlah karakter).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    _userClass,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  if (_userMotivation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ConstrainedBox(
                        // STEP: Motivasi juga rawan kepanjangan (max 2 baris
                        // di edit profile), jadi dibatasi 1 baris + ellipsis
                        // agar pill tidak melebar/merusak layout header.
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width - 80,
                        ),
                        child: Text(
                          '"$_userMotivation"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Menu
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _menuItem(
                    icon: Icons.edit_rounded,
                    label: 'Edit Profil',
                    onTap: () async {
                      await Navigator.pushNamed(context, '/edit-profile');
                      _loadUser();
                    },
                  ),
                  _menuItem(
                    icon: Icons.settings_rounded,
                    label: 'Pengaturan Aplikasi',
                    onTap: () =>
                        Navigator.pushNamed(context, '/settings'),
                  ),
                  _menuItem(
                    icon: Icons.info_outline_rounded,
                    label: 'Tentang Jeda',
                    onTap: () =>
                        Navigator.pushNamed(context, '/about'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Jeda v1.0.0 (Build 2026)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? const Color(0xFF1A1A2E), size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: color ?? const Color(0xFF1A1A2E),
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey[300], size: 20),
          ],
        ),
      ),
    );
  }
}