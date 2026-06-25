import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Navigasi ke halaman berikutnya setelah 2.5 detik
    // Ganti '/home' dengan route tujuanmu
    Timer(const Duration(milliseconds: 2500), () async {
  if (!mounted) return;

  final prefs = await SharedPreferences.getInstance();
  final isOnboarded = prefs.getBool('is_onboarded') ?? false;

  debugPrint('🔍 Splash: isOnboarded=$isOnboarded');

  if (mounted) {
    Navigator.pushReplacementNamed(
      context, 
      isOnboarded ? '/permission' : '/onboarding'
    );
  }
});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFC107), // kuning emas
              Color(0xFFF57C00), // oranye dalam
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo icon
                Image.asset(
                  'assets/icon/icon_jeda.png',
                  width: 130,
                  height: 130,
                ),

                const SizedBox(height: 28),

                // Nama aplikasi
                const Text(
                  'jeda.',
                  style: TextStyle(
                    fontFamily: 'Inter', // ganti sesuai font yang kamu pakai
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 10),

                // Tagline
                const Text(
                  'jeda sejenak, bertumbuh lebih baik.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}