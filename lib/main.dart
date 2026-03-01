import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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

void main() {
  runApp(const JedaApp());
}

class JedaApp extends StatelessWidget {
  const JedaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..initialize(),
      child: MaterialApp(
        title: 'JEDA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
          ),
          textTheme: GoogleFonts.poppinsTextTheme(),
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