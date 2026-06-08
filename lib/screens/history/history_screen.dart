import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:jeda_app/services/app_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatHours(double h) {
    int hours = h.toInt();
    int minutes = ((h - hours) * 60).toInt();
    if (hours > 0 && minutes > 0) return '${hours}j ${minutes}m';
    if (hours > 0) return '${hours}j';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final data = provider.data;

    // Buat list app dari data usage
    final List<Map<String, dynamic>> appList = [
      {
        'name': 'Sosial Media',
        'duration': data.socialMediaUsage,
        'icon': Icons.tag_rounded,
        'color': const Color(0xFFEC4899),
      },
      {
        'name': 'Gaming',
        'duration': data.gamingTime,
        'icon': Icons.sports_esports_rounded,
        'color': const Color(0xFF10B981),
      },
      {
        'name': 'Lainnya',
        'duration': data.dailyScreenTime -
            data.socialMediaUsage -
            data.gamingTime,
        'icon': Icons.apps_rounded,
        'color': const Color(0xFFFFC107),
      },
    ]..sort((a, b) =>
        (b['duration'] as double).compareTo(a['duration'] as double));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                'Aktivitas Harian',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle:
                      GoogleFonts.poppins(fontSize: 13),
                  labelColor: const Color(0xFF1A1A2E),
                  unselectedLabelColor: Colors.grey[400],
                  indicator: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Daftar Aplikasi'),
                    Tab(text: 'Log Deteksi'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Daftar Aplikasi
                  _buildAppList(appList, data.dailyScreenTime),

                  // Tab 2: Log Deteksi
                  _buildLogDeteksi(provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppList(
      List<Map<String, dynamic>> appList, double totalTime) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: appList.length,
      itemBuilder: (context, i) {
        final app = appList[i];
        final duration = app['duration'] as double;
        final percent =
            totalTime > 0 ? (duration / totalTime).clamp(0.0, 1.0) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (app['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  app['icon'] as IconData,
                  color: app['color'] as Color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          app['name'] as String,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        Text(
                          _formatHours(duration),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: app['color'] as Color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 4,
                        backgroundColor: Colors.grey[100],
                        color: app['color'] as Color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogDeteksi(AppProvider provider) {
  final now = DateTime.now();
  final timeStr =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final prediction = provider.prediction;
  final data = provider.data;
  final logs = <Map<String, dynamic>>[];

  // ── 1. STATUS MODEL (Waspada / Bahaya) ──────────────────────────
  if (prediction == 2) {
    logs.add({
      'time': timeStr,
      'title': 'Status: BAHAYA',
      'desc':
          'Model deteksi menunjukkan pola penggunaan berisiko tinggi berdasarkan durasi, sesi, dan notifikasi harian.',
      'color': const Color(0xFFEF4444),
      'icon': Icons.warning_rounded,
      'source': 'Kwon et al., 2013 — SAS-SV',
    });
  } else if (prediction == 1) {
    logs.add({
      'time': timeStr,
      'title': 'Status: WASPADA',
      'desc':
          'Penggunaan mendekati batas risiko. Kurangi durasi layar sebelum meningkat ke kategori bahaya.',
      'color': const Color(0xFFFFC107),
      'icon': Icons.info_rounded,
      'source': 'Kwon et al., 2013 — SAS-SV',
    });
  }

  // ── 2. DOMINASI SOSIAL MEDIA ─────────────────────────────────────
  if (data.dailyScreenTime > 0 &&
      (data.socialMediaUsage / data.dailyScreenTime) > 0.5) {
    logs.add({
      'time': timeStr,
      'title': 'Dominasi Sosial Media',
      'desc':
          'Lebih dari 50% waktu layarmu digunakan untuk sosial media. Remaja yang menggunakan sosmed >3 jam/hari berisiko lebih tinggi mengalami depresi dan kecemasan.',
      'color': const Color(0xFFEC4899),
      'icon': Icons.tag_rounded,
      'source': 'Springer Nature, 2025',
    });
  }

  // ── 3. PENGGUNAAN MALAM ──────────────────────────────────────────
  if (data.nightUsage > 0.5) {
    logs.add({
      'time': timeStr,
      'title': 'Penggunaan Malam Berlebihan',
      'desc':
          'Terdeteksi penggunaan smartphone >30 menit setelah pukul 22:00. Berkaitan dengan gangguan tidur dan penurunan kesehatan mental remaja.',
      'color': const Color(0xFF6366F1),
      'icon': Icons.nightlight_rounded,
      'source': 'Swedish Public Health Agency, 2024; Journal of Adolescence, 2024',
    });
  } else if (data.nightUsage > 0.0) {
    logs.add({
      'time': timeStr,
      'title': 'Aktivitas Malam Terdeteksi',
      'desc':
          'Terdeteksi penggunaan smartphone setelah pukul 22:00. Hindari layar minimal 1 jam sebelum tidur.',
      'color': const Color(0xFF8B5CF6),
      'icon': Icons.nightlight_outlined,
      'source': 'Swedish Public Health Agency, 2024',
    });
  }

  // ── 4. SOSIAL MEDIA DI MALAM HARI ───────────────────────────────
  if (data.nightUsage > 0.3 && data.socialMediaUsage > 1.0) {
    logs.add({
      'time': timeStr,
      'title': 'Sosial Media di Malam Hari',
      'desc':
          'Kombinasi penggunaan sosmed tinggi dan aktif di malam hari secara khusus berkaitan dengan gangguan tidur dan depresi pada remaja di 18 negara.',
      'color': const Color(0xFFF97316),
      'icon': Icons.bedtime_rounded,
      'source': 'Sleep Health Journal, 2023',
    });
  }

  // ── EMPTY STATE ──────────────────────────────────────────────────
  if (logs.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 60, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Tidak ada log deteksi hari ini',
            style: GoogleFonts.poppins(color: Colors.grey[400]),
          ),
          const SizedBox(height: 4),
          Text(
            'Penggunaanmu masih dalam batas aman 👍',
            style: GoogleFonts.poppins(
                fontSize: 12, color: Colors.grey[300]),
          ),
        ],
      ),
    );
  }

  // ── LIST ─────────────────────────────────────────────────────────
  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    itemCount: logs.length,
    itemBuilder: (context, i) {
      final log = logs[i];
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (log['color'] as Color).withOpacity(0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              log['time'] as String,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (log['color'] as Color).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                log['icon'] as IconData,
                color: log['color'] as Color,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log['title'] as String,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: log['color'] as Color,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    log['desc'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey[500],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📚 ${log['source']}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.grey[350],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
    }