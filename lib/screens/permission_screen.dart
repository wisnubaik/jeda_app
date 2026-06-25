import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:jeda_app/services/app_provider.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {   
      
       bool _isLoading = false;       // ← tambah mixin ini

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);   // ← daftarkan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().addListener(_checkAndNavigate);
    });
  }

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);  // ← tambah ini
  super.dispose();
}

  // Dipanggil setiap kali app kembali ke foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckPermission();
    }
  }

  Future<void> _recheckPermission() async {
    final provider = context.read<AppProvider>();
    await provider.checkPermission();   // cek ulang tanpa fetch data dulu
    _checkAndNavigate();
  }

  void _checkAndNavigate() {
    final provider = context.read<AppProvider>();
    if (provider.hasPermission && mounted) {
      provider.removeListener(_checkAndNavigate);
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _requestUsage() async {
  if (_isLoading) return;  // Prevent double tap
  
  setState(() => _isLoading = true);  // ← Set loading = true
  debugPrint('📱 Memulai request permissions...');

  final provider = context.read<AppProvider>();

  // STEP 1: Request Usage Stats Permission
  debugPrint('📊 [1/2] Requesting Usage Stats permission...');
  await provider.openUsageSettings();

  // Tunggu sebentar agar user sempat approve di Settings
  await Future.delayed(const Duration(seconds: 1));

  // STEP 2: Request Notification Listener Permission ← TEMPAT UTAMA TAMBAHAN
  debugPrint('🔔 [2/2] Requesting Notification Listener permission...');
  try {
    bool isNotifGranted =
        await NotificationListenerService.isPermissionGranted() ?? false;
    if (!isNotifGranted) {
      debugPrint('🔔 Notif listener belum granted, request sekarang...');
      await NotificationListenerService.requestPermission();
      isNotifGranted =
          await NotificationListenerService.isPermissionGranted() ?? false;
      debugPrint('🔔 Notif listener granted: $isNotifGranted');
    } else {
      debugPrint('🔔 Notif listener sudah granted sebelumnya');
    }
  } catch (e) {
    debugPrint('❌ Error saat request notif listener: $e');
  }

  // STEP 3: Re-check usage permission dan navigate
  debugPrint('✅ Kedua permission sudah diminta, cek ulang Usage Stats...');
  await provider.checkPermission();

  if (mounted) {
    setState(() => _isLoading = false);  // ← Set loading = false
    _checkAndNavigate();
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  size: 52,
                  color: Color(0xFFFFC107),
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'Akses Penggunaan',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Izinkan Jeda mengakses data penggunaan dan notifikasi agar fitur monitoring bisa berjalan dengan akurat.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.6,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestUsage,  // ← Disable saat loading
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading  // ← Show loading indicator
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          )
          : Text(
                    'Berikan Izin',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
