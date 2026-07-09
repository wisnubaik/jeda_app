import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'widgets/jeda_overlay_widget.dart';
import 'services/app_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/gatekeeper_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/home_screen.dart';
import 'screens/input_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/settings_screen.dart';
import 'screens/profile/about_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';


// ══════════════════════════════════════════════════════════
// GLOBAL NAVIGATOR KEY
// Dipakai agar AppProvider bisa menampilkan dialog (pop-up
// "SAATNYA JEDA!") dari MANA SAJA — tidak peduli halaman/route
// mana yang sedang aktif (Dashboard, Riwayat, Settings, dll).
// AppProvider akan import file ini untuk akses navigatorKey.
// ══════════════════════════════════════════════════════════
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ==========================================
// MESIN OVERLAY (ANTI BLACK-BAR INFINIX)
// ==========================================
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ FIX: Matikan fetch font saat runtime di overlay juga
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.expand(child: JedaOverlayWidget()),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tutup overlay yang mungkin masih menggantung dari sesi sebelumnya, dan
  // pastikan flag alarm dimatikan agar overlay yang re-attach saat startup
  // tidak membunyikan alarm.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_should_alarm', false);
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  } catch (_) {}

  GoogleFonts.config.allowRuntimeFetching = false;

  // ══════════════════════════════════════════════════════════
  // WORKMANAGER INIT
  // Daftarkan callback dispatcher (didefinisikan di app_provider.dart)
  // supaya task periodik tahu fungsi mana yang harus dijalankan
  // saat dipanggil sistem Android di background.
  // ══════════════════════════════════════════════════════════
  await Workmanager().initialize(callbackDispatcher);

  runApp(const JedaApp());
}

class JedaApp extends StatelessWidget {
  const JedaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..initialize(),
      child: MaterialApp(
        // ══════════════════════════════════════════════════
        // Daftarkan navigatorKey ke MaterialApp.
        // Setelah ini, AppProvider bisa panggil:
        //   navigatorKey.currentState!.context
        // untuk showDialog() dari halaman manapun.
        // ══════════════════════════════════════════════════
        navigatorKey: navigatorKey,
        title: 'JEDA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/gatekeeper': (_) => const GatekeeperScreen(),
          '/permission': (_) => const PermissionScreen(),
          '/home': (_) => const HomeScreen(),
          '/input': (_) => const InputScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/edit-profile': (_) => const EditProfileScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/about': (_) => const AboutScreen(),
        },
      ),
    );
  }
}