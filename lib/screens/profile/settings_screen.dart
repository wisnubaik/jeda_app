import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../../services/app_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _previewSound(String key) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$key.mp3'));
    } catch (e) {
      debugPrint('❌ preview sound: $e');
    }
  }

  Future<void> _previewVibration(String mode) async {
    final has = await Vibration.hasVibrator();
    if (has != true) return;
    await Vibration.cancel(); // hentikan getaran sebelumnya dulu
    switch (mode) {
      case 'off':
        break;
      case 'pendek':
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
        break;
      case 'panjang':
        Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1000]);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Notifikasi Suara (toggle ON/OFF) ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          provider.isSoundEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          color: const Color(0xFFFFC107),
                        ),
                      ),
                      const SizedBox(width: 14),
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
            ),

            const SizedBox(height: 28),

            // ── Pilihan Nada Alarm ──
            _sectionTitle('NADA ALARM', Icons.music_note_rounded),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !provider.isSoundEnabled,
              child: Opacity(
                opacity: provider.isSoundEnabled ? 1.0 : 0.4,
                child: Column(
                  children: [
                    _soundTile(
                      label: 'Default',
                      subtitle: 'Tegas & jelas',
                      emoji: '🔔',
                      color: const Color(0xFFFFC107),
                      soundKey: 'alarm',
                      selected: provider.alarmSound == 'alarm',
                      onSelect: () => provider.setAlarmSound('alarm'),
                    ),
                    _soundTile(
                      label: 'Lembut',
                      subtitle: 'Nada yang lebih halus',
                      emoji: '🎐',
                      color: const Color(0xFF6366F1),
                      soundKey: 'alarm_gentle',
                      selected: provider.alarmSound == 'alarm_gentle',
                      onSelect: () => provider.setAlarmSound('alarm_gentle'),
                    ),
                    _soundTile(
                      label: 'Mendesak',
                      subtitle: 'Untuk pengingat tegas',
                      emoji: '🚨',
                      color: const Color(0xFFEF4444),
                      soundKey: 'alarm_urgent',
                      selected: provider.alarmSound == 'alarm_urgent',
                      onSelect: () => provider.setAlarmSound('alarm_urgent'),
                    ),
                  ],
                ),
              ),
            ),
            if (!provider.isSoundEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Aktifkan Suara Alarm untuk memilih nada',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey[400]),
                ),
              ),

            const SizedBox(height: 28),

            // ── Intensitas Getaran ──
            _sectionTitle('INTENSITAS GETARAN', Icons.vibration_rounded),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _vibrationCard(
                    label: 'Mati',
                    icon: Icons.do_not_disturb_on_rounded,
                    color: Colors.grey,
                    mode: 'off',
                    selected: provider.vibrationMode == 'off',
                    onSelect: () => provider.setVibrationMode('off'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _vibrationCard(
                    label: 'Pendek',
                    icon: Icons.vibration_rounded,
                    color: const Color(0xFF6366F1),
                    mode: 'pendek',
                    selected: provider.vibrationMode == 'pendek',
                    onSelect: () => provider.setVibrationMode('pendek'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _vibrationCard(
                    label: 'Panjang',
                    icon: Icons.vibration_rounded,
                    color: const Color(0xFFEF4444),
                    mode: 'panjang',
                    selected: provider.vibrationMode == 'panjang',
                    onSelect: () => provider.setVibrationMode('panjang'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Pesan saat Jeda ──
            _sectionTitle('PESAN SAAT JEDA', Icons.chat_bubble_rounded),
            const SizedBox(height: 4),
            Text(
              'Pesan yang muncul saat status BAHAYA terdeteksi',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[400]),
            ),
            const SizedBox(height: 14),
            _motivationCard(
              label: 'Acak',
              subtitle: 'Pesan berganti setiap muncul',
              icon: Icons.shuffle_rounded,
              color: const Color(0xFF8B5CF6),
              selected: provider.motivationVariant == 0,
              onSelect: () => provider.setMotivationVariant(0),
            ),
            for (int i = 0; i < AppProvider.motivationTexts.length; i++)
              _motivationCard(
                label: 'Pesan ${i + 1}',
                subtitle: AppProvider.motivationTexts[i].replaceAll('\n', ' '),
                icon: _motivationIcons[i % _motivationIcons.length],
                color: _motivationColors[i % _motivationColors.length],
                selected: provider.motivationVariant == i + 1,
                onSelect: () => provider.setMotivationVariant(i + 1),
              ),
          ],
        ),
      ),
    );
  }

  static const _motivationIcons = [
    Icons.wb_sunny_rounded,
    Icons.self_improvement_rounded,
    Icons.directions_walk_rounded,
    Icons.air_rounded,
  ];

  static const _motivationColors = [
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFF6366F1),
  ];

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey[500],
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _soundTile({
    required String label,
    required String subtitle,
    required String emoji,
    required Color color,
    required String soundKey,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return GestureDetector(
      onTap: () {
        onSelect();
        _previewSound(soundKey);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03), blurRadius: 10)
                ],
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: const Color(0xFF1A1A2E))),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? color : Colors.grey[300],
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vibrationCard({
    required String label,
    required IconData icon,
    required Color color,
    required String mode,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return GestureDetector(
      onTap: () {
        onSelect();
        _previewVibration(mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03), blurRadius: 10)
                ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? color : Colors.grey[300],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _motivationCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03), blurRadius: 10)
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(
                    '"$subtitle"',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF1A1A2E),
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? color : Colors.grey[300],
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}