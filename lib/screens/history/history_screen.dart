import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:jeda_app/services/app_provider.dart';

const _systemPackages = {
  'android',
  'com.android.systemui',
  'com.wishnotregret.berijeda',
  'com.wishnotregret.jeda_app',
  'com.google.android.launcher',
  'com.android.launcher3',
  'com.transsion.settings.wifi',
  'com.transsion.resolver',
  'com.android.settings',
  'com.coloros.securitypermission',
};

const _knownAppNames = {
  'com.instagram.android': 'Instagram',
  'org.telegram.messenger': 'Telegram',
  'com.whatsapp': 'WhatsApp',
  'com.whatsapp.w4b': 'WhatsApp Business',
  'com.ss.android.ugc.trill': 'TikTok',
  'com.ss.android.ugc.aweme': 'TikTok',
  'com.twitter.android': 'X (Twitter)',
  'com.facebook.katana': 'Facebook',
  'com.snapchat.android': 'Snapchat',
  'com.android.chrome': 'Chrome',
  'com.android.vending': 'Play Store',
  'com.google.android.youtube': 'YouTube',
  'com.spotify.music': 'Spotify',
  'com.gojek.app': 'Gojek',
  'com.tokopedia.tkpd': 'Tokopedia',
  'com.shopee.id': 'Shopee',
};

const _avatarColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
  Color(0xFFF59E0B),
];

// ─────────────────────────────────────────────────────────────────────────────

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

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatHours(double h) {
    final hours = h.toInt();
    final minutes = ((h - hours) * 60).toInt();
    if (hours > 0 && minutes > 0) return '${hours}j ${minutes}m';
    if (hours > 0) return '${hours}j';
    return '${minutes}m';
  }

  String _categorizeBySystem(String pkg, int sysCategory) {
    debugPrint('📂 $pkg → category: $sysCategory');
  switch (sysCategory) {
    case 1: return 'game';
    case 4: return 'social';
    case 3: return 'video';
    case 5: return 'news';
    default: return 'other';
  }
}

  Color _colorFromPkg(String pkg) {
    final hash = pkg.codeUnits.fold(0, (a, b) => a + b);
    return _avatarColors[hash % _avatarColors.length];
  }

  // Helper: nama tampilan
  String _displayName(String pkg, Map<String, String> appNameMap) {
    // dari appNameMap (nama resmi dari sistem)
    final systemName = appNameMap[pkg];
    if (systemName != null && systemName.isNotEmpty) {
      return systemName[0].toUpperCase() + systemName.substring(1);
    }
    if (_knownAppNames.containsKey(pkg)) return _knownAppNames[pkg]!;
    //last resort: ambil bagian terakhir package name, capitalize
    final fallback = pkg.split('.').last;
    return fallback[0].toUpperCase() + fallback.substring(1);
  }

  // ─── Kategori helper ─────────────────────────────────────────────────────

  _CategorizedApps _categorize(Map<String, double> usageMap, Map<String, int> categoryMap) {
    final social = <MapEntry<String, double>>[];
    final game = <MapEntry<String, double>>[];
    final video = <MapEntry<String, double>>[];
    final news = <MapEntry<String, double>>[];
    final other = <MapEntry<String, double>>[];

    for (final e in usageMap.entries) {
  if (_systemPackages.contains(e.key)) continue;
  final cat = _categorizeBySystem(e.key, categoryMap[e.key] ?? -1);
  switch (cat) {
    case 'social': social.add(e); break;
    case 'game':   game.add(e);   break;
    case 'video':  video.add(e);  break;
    case 'news':   news.add(e);   break;
    default:       other.add(e);
  }
}

    return _CategorizedApps(
      social: social..sort((a, b) => b.value.compareTo(a.value)),
      game: game..sort((a, b) => b.value.compareTo(a.value)),
      video: video..sort((a, b) => b.value.compareTo(a.value)),
      news: news..sort((a, b) => b.value.compareTo(a.value)),
      other: other..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
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
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AppListTab(
                    provider: provider,
                    categorize: (usageMap) => _categorize(usageMap, provider.appCategoryMap),
                    colorFromPkg: _colorFromPkg,
                    displayName: _displayName,
                    formatHours: _formatHours,
                  ),
                  _LogDeteksiTab(provider: provider, formatHours: _formatHours),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data class sederhana ────────────────────────────────────────────────────

class _CategorizedApps {
  final List<MapEntry<String, double>> social;
  final List<MapEntry<String, double>> game;
  final List<MapEntry<String, double>> video;
  final List<MapEntry<String, double>> news;
  final List<MapEntry<String, double>> other;
  const _CategorizedApps({
    required this.social,
    required this.game,
    required this.video,
    required this.news,
    required this.other,
  });
}

// ─── Tab 1: Daftar Aplikasi ──────────────────────────────────────────────────

class _AppListTab extends StatelessWidget {
  final AppProvider provider;
  final _CategorizedApps Function(Map<String, double>) categorize;
  final Color Function(String) colorFromPkg;
  final String Function(String, Map<String, String>) displayName;
  final String Function(double) formatHours;

  const _AppListTab({
    required this.provider,
    required this.categorize,
    required this.colorFromPkg,
    required this.displayName,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    final cats = categorize(provider.appUsageMap);
    final totalTime = provider.data.dailyScreenTime;

// Hitung total per kategori
    final socialTotal = cats.social.fold(0.0, (s, e) => s + e.value);
    final gameTotal = cats.game.fold(0.0, (s, e) => s + e.value);
    final videoTotal = cats.video.fold(0.0, (s, e) => s + e.value);
    final newsTotal = cats.news.fold(0.0, (s, e) => s + e.value);
    final otherTotal = cats.other.fold(0.0, (s, e) => s + e.value);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _SummaryCard(
          totalTime: totalTime,
          activeApps: provider.appUsageMap.length,
          formatHours: formatHours,
        ),
        const SizedBox(height: 12),
        _CategorySection(
          title: 'Sosial Media',
          apps: cats.social,
          color: const Color(0xFFEC4899),
          icon: Icons.tag_rounded,
          catTotal: socialTotal,
          totalTime: totalTime,
          colorFromPkg: colorFromPkg,
          displayName: (pkg) => displayName(pkg, provider.appNameMap),
          formatHours: formatHours,
        ),
        _CategorySection(
          title: 'Gaming',
          apps: cats.game,
          color: const Color(0xFF10B981),
          icon: Icons.sports_esports_rounded,
          catTotal: gameTotal,
          totalTime: totalTime,
          colorFromPkg: colorFromPkg,
          displayName: (pkg) => displayName(pkg, provider.appNameMap),
          formatHours: formatHours,
        ),
        _CategorySection(
          title: 'Video',
          apps: cats.video,
          color: const Color(0xFF3B82F6),
          icon: Icons.video_library_rounded,
          catTotal: videoTotal,
          totalTime: totalTime,
          colorFromPkg: colorFromPkg,
          displayName: (pkg) => displayName(pkg, provider.appNameMap),
          formatHours: formatHours,
        ),
        _CategorySection(
          title: 'Berita',
          apps: cats.news,
          color: const Color(0xFF8B5CF6),
          icon: Icons.newspaper,
          catTotal: newsTotal,
          totalTime: totalTime,
          colorFromPkg: colorFromPkg,
          displayName: (pkg) => displayName(pkg, provider.appNameMap),
          formatHours: formatHours,
        ),
        _CategorySection(
          title: 'Lainnya',
          apps: cats.other,
          color: const Color(0xFFFFC107),
          icon: Icons.apps_rounded,
          catTotal: otherTotal,
          totalTime: totalTime,
          colorFromPkg: colorFromPkg,
          displayName: (pkg) => displayName(pkg, provider.appNameMap),
          formatHours: formatHours,
        ),
      ],
    );
  }
}

// ─── Summary Card ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double totalTime;
  final int activeApps;
  final String Function(double) formatHours;

  const _SummaryCard({
    required this.totalTime,
    required this.activeApps,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Screen Time',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white60)),
              Text(formatHours(totalTime),
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Hari ini',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.white38)),
              Text('$activeApps app aktif',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white60)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Category Section ────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final String title;
  final List<MapEntry<String, double>> apps;
  final Color color;
  final IconData icon;
  final double catTotal;
  final double totalTime;
  final Color Function(String) colorFromPkg;
  final String Function(String) displayName;
  final String Function(double) formatHours;

  const _CategorySection({
    required this.title,
    required this.apps,
    required this.color,
    required this.icon,
    required this.catTotal,
    required this.totalTime,
    required this.colorFromPkg,
    required this.displayName,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF1A1A2E),
                      )),
                ),
                Text(formatHours(catTotal),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    )),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 10),
          ...apps.map((e) => _AppItem(
                pkg: e.key,
                hours: e.value,
                totalTime: totalTime,
                color: colorFromPkg(e.key),
                displayName: displayName(e.key),
                formatHours: formatHours,
              )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── App Item ────────────────────────────────────────────────────────────────

class _AppItem extends StatelessWidget {
  final String pkg;
  final double hours;
  final double totalTime;
  final Color color;
  final String displayName;
  final String Function(double) formatHours;

  const _AppItem({
    required this.pkg,
    required this.hours,
    required this.totalTime,
    required this.color,
    required this.displayName,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final percent =
        totalTime > 0 ? (hours / totalTime).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(initial,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(displayName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1A1A2E),
                        )),
                    Text(formatHours(hours),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        )),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 3,
                    backgroundColor: Colors.grey[100],
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 2: Log Deteksi ──────────────────────────────────────────────────────

class _LogDeteksiTab extends StatelessWidget {
  final AppProvider provider;
  final String Function(double) formatHours;

  const _LogDeteksiTab({required this.provider, required this.formatHours});

  @override
  Widget build(BuildContext context) {
    final logs = provider.detectionLogs;

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 60, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('Tidak ada log deteksi hari ini',
                style: GoogleFonts.poppins(color: Colors.grey[400])),
            const SizedBox(height: 4),
            Text('Penggunaanmu masih dalam batas aman 👍',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[300])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: logs.length,
      itemBuilder: (context, i) {
        final log = logs[i];
        final color = log['color'] as Color;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log['time'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                  )),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(log['icon'] as IconData, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log['title'] as String,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontSize: 13,
                        )),
                    const SizedBox(height: 3),
                    Text(log['desc'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[500],
                          height: 1.5,
                        )),
                    const SizedBox(height: 4),
                    Text('📚 ${log['source']}',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic,
                        )),
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