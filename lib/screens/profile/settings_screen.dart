import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/app_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _snoozeDuration = 15;

  @override
  void initState() {
    super.initState();
    _loadSnooze();
  }

  Future<void> _loadSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _snoozeDuration = prefs.getInt('snooze_duration') ?? 15;
    });
  }

  Future<void> _saveSnooze(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('snooze_duration', val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A2E)),
        ),
        title: Text(
          'Pengaturan',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: SingleChildScrollView(
  padding: const EdgeInsets.all(20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

            // ── Notifikasi Suara ──
            Consumer<AppProvider>(
              builder: (context, provider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            provider.isSoundEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: const Color(0xFFFFC107),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Suara Alarm',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: provider.isSoundEnabled,
                        onChanged: (v) => provider.toggleSound(v),
                        activeColor: const Color(0xFFFFC107),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // ── Durasi Snooze ──
            Text(
              'DURASI DEFAULT SNOOZE',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [15, 30, 60].map((duration) {
                final isSelected = _snoozeDuration == duration;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _snoozeDuration = duration);
                      _saveSnooze(duration);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFC107)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$duration Menit',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isSelected
                              ? Colors.white
                              : Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            // ── TOMBOL TEST (HAPUS SETELAH SIDANG) ──
const SizedBox(height: 20),
Text(
  'MODE DEMO',
  style: GoogleFonts.poppins(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Colors.grey[500],
    letterSpacing: 0.5,
  ),
),
const SizedBox(height: 12),
GestureDetector(
  onTap: () {
    context.read<AppProvider>().updateData(
      screenTime: 9.5,
      appSessions: 90,
      notifications: 200,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Mode BAHAYA aktif untuk demo!'),
        backgroundColor: Colors.red,
      ),
    );
  },
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: Colors.red,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '🔴 Simulasi Mode BAHAYA',
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: Colors.white,
      ),
    ),
  ),
),
const SizedBox(height: 8),
GestureDetector(
  onTap: () {
    context.read<AppProvider>().fetchUsageData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Data dikembalikan ke real'),
        backgroundColor: Colors.green,
      ),
    );
  },
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: Colors.green,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '🟢 Kembalikan ke Data Real',
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: Colors.white,
      ),
    ),
  ),
),
          ],
        ),
      ),
    );
  }
}