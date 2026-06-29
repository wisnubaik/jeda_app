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
  bool _isLoading = false;
  bool _usageGranted = false;
  bool _notifGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().addListener(_checkAndNavigate);
      _checkInitialState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// ═════════════════════════════════════════════════════════════════
  /// CHECK INITIAL PERMISSION STATE
  /// Dipanggil saat screen pertama kali dimuat
  /// ═════════════════════════════════════════════════════════════════
  Future<void> _checkInitialState() async {
    final provider = context.read<AppProvider>();

    // Paksa cek ulang ke sistem Android secara langsung, jangan asumsikan
    // provider.hasPermission sudah ter-update (provider.initialize() bisa
    // saja masih berjalan di background saat screen ini pertama dimuat).
    await provider.checkPermission();

    bool usageGranted = provider.hasPermission;

    bool notifGranted =
        await NotificationListenerService.isPermissionGranted() ?? false;

    if (mounted) {
      setState(() {
        _usageGranted = usageGranted;
        _notifGranted = notifGranted;
      });
      debugPrint('🔍 Initial check - Usage: $_usageGranted, Notif: $_notifGranted');
      _checkAndNavigate();
    }
  }

  /// ═════════════════════════════════════════════════════════════════
  /// APP LIFECYCLE: Dipanggil setiap kali app kembali ke foreground
  /// ═════════════════════════════════════════════════════════════════
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckPermission();
    }
  }

  /// ═════════════════════════════════════════════════════════════════
  /// RECHECK BOTH PERMISSIONS
  /// Dipanggil saat app resume dari Settings
  /// ═════════════════════════════════════════════════════════════════
  Future<void> _recheckPermission() async {
    final provider = context.read<AppProvider>();
    await provider.checkPermission();

    // Cek notif listener juga
    bool notifGranted =
        await NotificationListenerService.isPermissionGranted() ?? false;

    if (mounted) {
      setState(() {
        _usageGranted = provider.hasPermission;
        _notifGranted = notifGranted;
      });
      debugPrint('🔄 App resumed - Usage: $_usageGranted, Notif: $_notifGranted');
    }

    _checkAndNavigate();
  }

  /// ═════════════════════════════════════════════════════════════════
  /// BLOCKING NAVIGATION CHECK
  /// Hanya navigate ke /home jika KEDUA permission sudah granted
  /// ═════════════════════════════════════════════════════════════════
  void _checkAndNavigate() {
    if (!mounted) return;

    // Sinkronkan _usageGranted dengan provider.hasPermission setiap kali
    // listener ini terpanggil (dipicu oleh notifyListeners() di
    // AppProvider, termasuk saat initialize()/checkPermission() selesai).
    // Tanpa ini, _usageGranted bisa "nyangkut" di nilai lama walau
    // provider.hasPermission sudah benar, karena keduanya adalah
    // variabel state yang berbeda dan tidak otomatis sinkron.
    final provider = context.read<AppProvider>();
    if (_usageGranted != provider.hasPermission) {
      setState(() {
        _usageGranted = provider.hasPermission;
      });
    }

    if (_usageGranted && _notifGranted && mounted) {
      context.read<AppProvider>().removeListener(_checkAndNavigate);
      debugPrint('✅ KEDUA permission granted! Navigate ke /home');
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      debugPrint('❌ Belum semua permission granted. Tetap di Permission Screen.');
    }
  }

  /// ═════════════════════════════════════════════════════════════════
  /// REQUEST BOTH PERMISSIONS
  /// User tekan tombol "Aktifkan Kedua Izin"
  /// ═════════════════════════════════════════════════════════════════
  Future<void> _requestUsage() async {
    if (_isLoading) return; // Prevent double tap

    setState(() => _isLoading = true);
    debugPrint('📱 Memulai request permissions...');

    final provider = context.read<AppProvider>();

    // ───────────────────────────────────────────────────────────────
    // STEP 1: Request Usage Stats Permission
    // ───────────────────────────────────────────────────────────────
    debugPrint('📊 [1/2] Requesting Usage Stats permission...');
    await provider.openUsageSettings();

    // Tunggu sebentar agar user sempat approve di Settings
    await Future.delayed(const Duration(seconds: 1));

    // ───────────────────────────────────────────────────────────────
    // STEP 2: Request Notification Listener Permission
    // ───────────────────────────────────────────────────────────────
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

    // ───────────────────────────────────────────────────────────────
    // STEP 3: Re-check KEDUA permission
    // ───────────────────────────────────────────────────────────────
    debugPrint('✅ Kedua permission sudah diminta, cek ulang...');
    await provider.checkPermission();

    bool notifGranted =
        await NotificationListenerService.isPermissionGranted() ?? false;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _usageGranted = provider.hasPermission;
        _notifGranted = notifGranted;
      });
      debugPrint(
          '📊 Final check - Usage: $_usageGranted, Notif: $_notifGranted');
      _checkAndNavigate();
    }
  }

  /// ═════════════════════════════════════════════════════════════════
  /// BUILD PERMISSION ITEM WIDGET
  /// Menampilkan status setiap permission dengan icon & checkmark
  /// ═════════════════════════════════════════════════════════════════
  Widget _buildPermissionItem({
    required IconData icon,
    required String label,
    required String description,
    required bool isGranted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isGranted
            ? const Color(0xFFF0FDF4) // Light green background
            : const Color(0xFFFEF2F2), // Light red background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? const Color(0xFFC6F6D5) // Green border
              : const Color(0xFFFECACA), // Red border
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Icon dengan background
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted
                  ? const Color(0xFF86EFAC) // Green
                  : const Color(0xFFFCA5A5), // Red
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGranted ? Icons.check_rounded : icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Label & description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Status icon
          Icon(
            isGranted ? Icons.check_circle_rounded : Icons.pending_outlined,
            color: isGranted
                ? const Color(0xFF22C55E) // Green checkmark
                : const Color(0xFFFCA5A5), // Red pending
            size: 24,
          ),
        ],
      ),
    );
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

              // ═══════════════════════════════════════════════════════
              // ICON
              // ═══════════════════════════════════════════════════════
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 52,
                  color: Color(0xFFFFC107),
                ),
              ),
              const SizedBox(height: 32),

              // ═══════════════════════════════════════════════════════
              // TITLE
              // ═══════════════════════════════════════════════════════
              Text(
                'Izin Akses Diperlukan',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),

              // ═══════════════════════════════════════════════════════
              // DESCRIPTION
              // ═══════════════════════════════════════════════════════
              Text(
                'Jeda membutuhkan 2 izin penting agar monitoring bisa berjalan dengan akurat:',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 32),

              // ═══════════════════════════════════════════════════════
              // PERMISSION ITEM 1: Usage Stats
              // ═══════════════════════════════════════════════════════
              _buildPermissionItem(
                icon: Icons.bar_chart_rounded,
                label: 'Akses Data Penggunaan',
                description: 'Untuk menghitung screen time Anda',
                isGranted: _usageGranted,
              ),

              const SizedBox(height: 16),

              // ═══════════════════════════════════════════════════════
              // PERMISSION ITEM 2: Notification Listener
              // ═══════════════════════════════════════════════════════
              _buildPermissionItem(
                icon: Icons.notifications_active_rounded,
                label: 'Akses Notifikasi',
                description: 'Untuk menghitung jumlah notifikasi',
                isGranted: _notifGranted,
              ),

              const SizedBox(height: 48),

              // ═══════════════════════════════════════════════════════
              // WARNING TEXT (if not all permissions granted)
              // ═══════════════════════════════════════════════════════
              if (!_usageGranted || !_notifGranted) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFCD34D),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Kedua izin harus diaktifkan untuk melanjutkan.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF92400E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ═══════════════════════════════════════════════════════
              // BUTTON
              // ═══════════════════════════════════════════════════════
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestUsage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Aktifkan Kedua Izin',
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