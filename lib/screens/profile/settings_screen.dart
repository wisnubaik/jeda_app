import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _soundEnabled = true;
  int _snoozeDuration = 15;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _soundEnabled = prefs.getBool('sound_enabled') ?? true;
      _snoozeDuration = prefs.getInt('snooze_duration') ?? 15;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', _soundEnabled);
    await prefs.setInt('snooze_duration', _snoozeDuration);
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notifikasi Suara
            Container(
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
                      const Icon(Icons.volume_up_rounded,
                          color: Color(0xFFFFC107)),
                      const SizedBox(width: 12),
                      Text(
                        'Notifikasi Suara',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _soundEnabled,
                    onChanged: (v) {
                      setState(() => _soundEnabled = v);
                      _saveSettings();
                    },
                    activeColor: const Color(0xFFFFC107),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Durasi Snooze
            Text(
              'Durasi Default Snooze',
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
                      _saveSettings();
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
          ],
        ),
      ),
    );
  }
}