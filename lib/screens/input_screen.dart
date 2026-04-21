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
  // Hanya 4 Controller untuk 3 Fitur (Screen Time dipecah jadi Jam & Menit)
  final _jamCtrl = TextEditingController();
  final _menitCtrl = TextEditingController();
  final _unlocksCtrl = TextEditingController();
  final _notifCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = context.read<AppProvider>().data;
    
    // Pecah data desimal screen time kembali menjadi jam dan menit untuk UI
    int jam = data.dailyScreenTime.toInt();
    int menit = ((data.dailyScreenTime - jam) * 60).round();

    _jamCtrl.text = jam.toString();
    _menitCtrl.text = menit.toString();
    // Menggunakan appSessions sebagai parameter Unlocks (Frekuensi Dibuka)
    _unlocksCtrl.text = data.appSessions.toString(); 
    _notifCtrl.text = data.notifications.toString();
  }

  @override
  void dispose() {
    _jamCtrl.dispose();
    _menitCtrl.dispose();
    _unlocksCtrl.dispose();
    _notifCtrl.dispose();
    super.dispose();
  }

  void _save() {
    // Gabungkan input Jam dan Menit menjadi desimal untuk perhitungan Naive Bayes
    double screenTime = (double.tryParse(_jamCtrl.text) ?? 0) +
        ((double.tryParse(_menitCtrl.text) ?? 0) / 60);

    context.read<AppProvider>().updateData(
          screenTime: screenTime,
          appSessions: int.tryParse(_unlocksCtrl.text) ?? 0,
          notifications: int.tryParse(_notifCtrl.text) ?? 0,
          // Set fitur lama menjadi 0 agar tidak error di provider (bisa dihapus jika provider sudah di-update)
          socialMedia: 0,
          gaming: 0,
          nightUsage: 0,
          appsInstalled: 0,
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
          'Analisis Pola Penggunaan',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A2E)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KOTAK 1: SCREEN TIME (Lebih besar, dengan 2 kolom input)
            _buildScreenTimeCard(),
            
            // KOTAK 2: FREKUENSI DIBUKA (Unlocks)
            _buildLargeCard(
              controller: _unlocksCtrl,
              label: 'Frekuensi Dibuka (Unlocks)',
              subtitle: 'Berapa kali layar HP dinyalakan hari ini',
              unit: 'kali',
              icon: Icons.lock_open_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            
            // KOTAK 3: NOTIFIKASI
            _buildLargeCard(
              controller: _notifCtrl,
              label: 'Jumlah Notifikasi',
              subtitle: 'Total notifikasi masuk hari ini',
              unit: 'pesan',
              icon: Icons.notifications_active_rounded,
              color: const Color(0xFFF59E0B),
            ),

            const SizedBox(height: 32),
            
            // TOMBOL AKSI UTAMA
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: const Color(0xFF1A1A2E).withOpacity(0.4),
              ),
              child: Text(
                'Analisis Pola & Deteksi',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // WIDGET KHUSUS KOTAK SCREEN TIME (Jam & Menit Berdampingan)
  Widget _buildScreenTimeCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waktu Layar',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Total screen time harian',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSimpleInput(_jamCtrl, 'Jam'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSimpleInput(_menitCtrl, 'Menit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // WIDGET KOTAK BESAR UNTUK FITUR LAINNYA
  Widget _buildLargeCard({
    required TextEditingController controller,
    required String label,
    required String subtitle,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSimpleInput(controller, unit),
        ],
      ),
    );
  }

  // WIDGET TEXT FIELD STANDAR
  Widget _buildSimpleInput(TextEditingController controller, String unit) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        suffixText: unit,
        suffixStyle: GoogleFonts.poppins(
          color: Colors.grey[400],
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: const Color(0xFFF8F9FA), // Latar dalam field sedikit abu
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1A1A2E), width: 1.5),
        ),
      ),
    );
  }
}