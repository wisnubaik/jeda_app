import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';

class JedaOverlayWidget extends StatelessWidget {
  const JedaOverlayWidget({super.key});

  // Kirim pesan ke main isolate lalu tutup overlay
  Future<void> _snooze(int seconds) async {
    await FlutterOverlayWindow.shareData({
      'action': 'snooze',
      'seconds': seconds,
    });
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _disableMonitoring() async {
    await FlutterOverlayWindow.shareData({'action': 'disable_monitoring'});
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF97316),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wb_sunny_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'SAATNYA JEDA!',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF97316),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pola penggunaanmu sudah berlebihan.\nMata dan pikiranmu butuh istirahat.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _buildBtn(
                'Ingatkan 5 Detik Lagi',
                isPrimary: true,
                onTap: () => _snooze(5),
              ),
              const SizedBox(height: 10),
              _buildBtn(
                'Ingatkan 10 Detik Lagi',
                isPrimary: true,
                onTap: () => _snooze(10),
              ),
              const SizedBox(height: 10),
              _buildBtn(
                'Ingatkan 1 Menit Lagi',
                isPrimary: false,
                onTap: () => _snooze(60),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _disableMonitoring,
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                    children: [
                      const TextSpan(text: 'Saya sedang produktif. '),
                      TextSpan(
                        text: 'Matikan\nmonitoring hari ini!',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                          decoration: TextDecoration.underline,
                        ),
                      ),
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

  Widget _buildBtn(
    String label, {
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFFF59E0B) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side:
                isPrimary
                    ? BorderSide.none
                    : BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
