import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usage_stats/usage_stats.dart';
import '../services/app_provider.dart';
import 'dashboard_screen.dart';
import 'history/history_screen.dart';
import 'profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isDialogShowing = false;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _logicPengecekanIzin(),
    );
  }

  Future<void> _logicPengecekanIzin() async {
  if (_isDialogShowing) return;

  final p = context.read<AppProvider>();

  // Hanya cek Usage Stats — aksesibilitas sudah dicek di dashboard
  bool hasUsage = await UsageStats.checkUsagePermission() ?? false;
  if (!hasUsage) {
    await _tampilkanDialog(
      "Izin Akses Data",
      "Jeda butuh izin ini untuk menghitung Screen Time kamu secara akurat.",
      () => p.openUsageSettings(),
    );
  }
}

  Future<void> _tampilkanDialog(
    String t,
    String d,
    VoidCallback action,
  ) async {
    setState(() => _isDialogShowing = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        content: Text(d),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Nanti"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c);
              action();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("Buka Pengaturan"),
          ),
        ],
      ),
    );
    setState(() => _isDialogShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: Colors.orange,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Riwayat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}