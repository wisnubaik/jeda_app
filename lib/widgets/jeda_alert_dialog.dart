import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:jeda_app/services/app_provider.dart';

class JedaAlertDialog extends StatelessWidget {
  const JedaAlertDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => const JedaAlertDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wb_sunny_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),

            // Judul
            Text(
              'SAATNYA JEDA!',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFF97316),
              ),
            ),
            const SizedBox(height: 8),

            // Subjudul
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

            // Tombol snooze
            _buildButton(
              label: 'Ingatkan 15 Menit Lagi',
              isPrimary: true,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            _buildButton(
              label: 'Ingatkan 30 Menit Lagi',
              isPrimary: true,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            _buildButton(
              label: 'Ingatkan 1 Jam Lagi',
              isPrimary: false,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 20),

            // Dismiss
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  children: [
                    const TextSpan(text: 'Saya sedang produktif. '),
                    TextSpan(
                      text: 'Matikan monitoring hari ini!',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildButton({
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isPrimary ? const Color(0xFFF5A623) : Colors.white,
          foregroundColor:
              isPrimary ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}