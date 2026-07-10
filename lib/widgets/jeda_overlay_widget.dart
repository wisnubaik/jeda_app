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

  // Pesan default; akan ditimpa oleh nilai dari shareData (pilihan pengguna
  // di halaman Pengaturan).
  String _message = 'Pola penggunaanmu sudah berlebihan.\nWaktunya istirahat sejenak.';

  // Logo & warna per pesan — HARUS sama urutannya dengan _motivationIcons /
  // _motivationColors di halaman Pengaturan (settings_screen.dart).
  static const List<IconData> _icons = [
    Icons.wb_sunny_rounded,
    Icons.self_improvement_rounded,
    Icons.directions_walk_rounded,
    Icons.air_rounded,
  ];
  static const List<Color> _colors = [
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFF6366F1),
  ];

  IconData _icon = Icons.wb_sunny_rounded;
  Color _color = const Color(0xFFF97316);

  @override
  void initState() {
    super.initState();
    // Alarm & konfigurasi diterima via shareData dari isolate utama (nilai
    // selalu terbaru). Overlay yang re-attach saat startup tidak menerima
    // sinyal ini sehingga tidak berbunyi.
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event['action'] == 'alarm') {
        // Perbarui pesan sesuai pilihan pengguna di Pengaturan.
        final msg = event['message'];
        final idx = event['variant_index'];
        debugPrint('💬 [OVERLAY] pesan diterima: "$msg" (index=$idx)');
        if (mounted) {
          setState(() {
            if (msg is String && msg.isNotEmpty) _message = msg;
            if (idx is int && idx >= 0 && idx < _icons.length) {
              _icon = _icons[idx];
              _color = _colors[idx];
            }
          });
        }
        _playAlarm(
          soundOn: event['sound_enabled'] as bool? ?? true,
          alarm: event['alarm_sound'] as String? ?? 'alarm',
          vibMode: event['vibration_mode'] as String? ?? 'pendek',
        );
      }
    });
  }

  Future<void> _playAlarm({
    required bool soundOn,
    required String alarm,
    required String vibMode,
  }) async {
    debugPrint('🔊 [OVERLAY] _playAlarm (nyata): sound=$soundOn alarm=$alarm vib=$vibMode');
    try {
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

  @override
  Widget build(BuildContext context) {
    // Posisi kartu digeser sedikit ke bawah dari tengah (faktor 0.3) untuk
    // mengimbangi window overlay yang pada sebagian ROM tidak setinggi layar
    // penuh sehingga Center murni tampak agak ke atas. Nilai 0.3 dipilih agar
    // pop-up berada di area tengah yang nyaman dilihat.
    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Align(
          alignment: const Alignment(0, 0.5),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, vertical: 32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration:
                        BoxDecoration(color: _color, shape: BoxShape.circle),
                    child: Icon(_icon, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 24),
                  Text('SAATNYA JEDA!',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: _color,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: Colors.grey[600], height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24))),
                      onPressed: () => _snooze(10),
                      child: Text('Ingatkan 10 Detik Lagi',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A2E),
                          side: BorderSide(
                              color: Colors.grey[300]!, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24))),
                      onPressed: () => _snooze(600),
                      child: Text('Ingatkan 10 Menit Lagi',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: _disableMonitoring,
                    behavior: HitTestBehavior.opaque,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey[500]),
                        children: [
                          const TextSpan(text: 'Saya sedang produktif. '),
                          TextSpan(
                              text: 'Matikan\nmonitoring hari ini!',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                  decoration: TextDecoration.underline)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
