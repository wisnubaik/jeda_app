import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
          'Tentang Jeda',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.wb_sunny_rounded,
                size: 56,
                color: Color(0xFFFFC107),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Jeda v1.0',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dikembangkan oleh',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey[400]),
            ),
            Text(
              'Wisnu Adi Pradana',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            Text(
              'untuk Tugas Akhir.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey[400]),
            ),
            const SizedBox(height: 40),
            Text(
              '© 2026 Jeda Project',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey[300]),
            ),
          ],
        ),
      ),
    );
  }
}