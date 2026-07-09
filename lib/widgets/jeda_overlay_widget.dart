import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

class JedaOverlayWidget extends StatefulWidget {
  const JedaOverlayWidget({super.key});

  @override
  State<JedaOverlayWidget> createState() => _JedaOverlayWidgetState();
}

class _JedaOverlayWidgetState extends State<JedaOverlayWidget> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Dengarkan sinyal dari isolate utama. Alarm HANYA berbunyi bila menerima
    // shareData {'action':'alarm'} yang dikirim showJedaOverlay saat deteksi
    // Bahaya. Overlay yang re-attach saat startup tidak menerima sinyal ini,
    // sehingga tidak berbunyi.
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event['action'] == 'alarm') {
        _playAlarm();
      }
    });
  }

  Future<void> _playAlarm() async {
    debugPrint('🔊 [OVERLAY] _playAlarm dipanggil (peringatan nyata)');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final soundOn = prefs.getBool('flutter.sound_enabled') ?? true;
      final alarm = prefs.getString('flutter.alarm_sound') ?? 'alarm';
      final vibMode = prefs.getString('flutter.vibration_mode') ?? 'pendek';

      if (soundOn) {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.play(AssetSource('sounds/$alarm.mp3'));
      }
      if (vibMode != 'off') {
        final hasVib = await Vibration.hasVibrator() ?? false;
        if (hasVib) {
          if (vibMode == 'panjang') {
            Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1000]);
          } else {
            Vibration.vibrate(pattern: [0, 200, 100, 200]);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [OVERLAY] gagal play alarm: $e');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _snooze(int seconds) async {
    await _stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (seconds >= 600) {
        await prefs.setBool('overlay_snoozeLong', true);
      } else {
        await prefs.setBool('overlay_snoozeShort', true);
      }
      await prefs.reload();
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _disableMonitoring() async {
    await _stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('overlay_disableMonitoring', true);
      await prefs.reload();
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Align(
          alignment: const Alignment(0, 0.15),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF97316),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wb_sunny_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                Text('SAATNYA JEDA!',
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFF97316))),
                const SizedBox(height: 6),
                Text(
                  'Pola penggunaanmu sudah berlebihan.\nWaktunya istirahat sejenak.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey[600], height: 1.4),
                ),
                const SizedBox(height: 18),
                _buildBtn('Ingatkan 10 Detik Lagi',
                    isPrimary: true, onTap: () => _snooze(10)),
                const SizedBox(height: 9),
                _buildBtn('Ingatkan 10 Menit Lagi',
                    isPrimary: false, onTap: () => _snooze(600)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _disableMonitoring,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: Colors.grey[500]),
                        children: [
                          const TextSpan(text: 'Saya sedang produktif. '),
                          TextSpan(
                              text: 'Matikan monitoring hari ini!',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                  decoration: TextDecoration.underline)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBtn(String label,
      {required bool isPrimary, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFFF59E0B) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 13),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}
