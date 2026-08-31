import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/accessibility_notifier.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/navigation/navigation_screen.dart';
import 'features/vision_assist/vision_assist_screen.dart';
import 'features/gesture_sos/gesture_sos_screen.dart';
import 'features/profile/profile_screen.dart';

import 'features/navigation/map_loader.dart';
import 'features/vision_assist/camera_loader.dart';
import 'core/tts_helper.dart';
import 'core/services/background_navigation_service.dart';
import 'core/services/recovery_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMapIframe();
  registerWebcamView();
  await BackgroundNavigationService.init();
  // Check for interrupted navigation session (Recovery Manager)
  final hasRecovery = await RecoveryManager().hasActiveSession();
  if (hasRecovery) {
    debugPrint('[Main] Found interrupted navigation session — will prompt resume');
  }
  runApp(
    const ProviderScope(
      child: AccessibilityAssistantApp(),
    ),
  );
}

class AccessibilityAssistantApp extends ConsumerWidget {
  const AccessibilityAssistantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = ref.watch(accessibilityProvider);

    // Dynamic Color Palette: Volcanic Ash theme (Purple/Orange default, Blue/Amber for colorblind)
    final Color primaryColor = acc.colorBlind 
        ? const Color(0xFF0D47A1) // Colorblind-friendly Blue
        : const Color(0xFF8338EC); // Volcanic Ash Purple

    final Color secondaryColor = acc.colorBlind
        ? const Color(0xFFFFB300) // Colorblind-friendly Amber
        : const Color(0xFFFB5607); // Volcanic Ash Orange

    final Widget app = MaterialApp(
      title: 'Accessibility Assistant',
      debugShowCheckedModeBanner: false,

      // Global text scaling based on user preference
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(acc.fontScale),
          ),
          child: child!,
        );
      },

      // Theme configuration
      themeMode: acc.highContrast ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFE9ECEF), // Volcanic Ash Off-white background
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: secondaryColor,
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFDDE1E5), width: 1.5), // Volcanic Ash border tint
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: secondaryColor, width: 2.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF212529), // Volcanic Ash Dark Grey/Black background
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFFFB5607), // Volcanic Ash Orange
          surface: Color(0xFF212529), // Volcanic Ash Dark Grey/Black
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF212529),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E2125),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2125),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      // Splash screen determines initial route
      home: const SplashScreen(),
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/navigation': (context) => const NavigationScreen(),
        '/vision': (context) => const VisionAssistScreen(),
        '/sos': (context) => const GestureSosScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
    );

    // If viewed on desktop, wrap the ENTIRE MaterialApp inside the device frame.
    // This scales and positions platform views correctly without coordinate shift.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          return Container(
            color: const Color(0xFFECEFF1), // Light grey desktop background
            child: Center(
              child: Container(
                width: 412,
                height: 840,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(44),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 36,
                      spreadRadius: 4,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF37474F), // Premium dark metallic border bezel
                    width: 14,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: app,
                ),
              ),
            ),
          );
        }
        return app;
      },
    );
  }
}

/// Splash screen that checks onboarding completion and auth state
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    announceSpeech("ยินดีต้อนรับสู่แอปพลิเคชัน TAM การเปลี่ยนแปลงการเข้าถึงเพื่อทุกคน", true);
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    bool onboardingDone = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      onboardingDone = prefs.getBool('onboarding_complete') ?? false;
    } catch (e) {
      // Handle iframe localStorage restriction gracefully
      onboardingDone = false;
    }

    if (!mounted) return;

    if (!onboardingDone) {
      Navigator.pushReplacementNamed(context, '/onboarding');
    } else {
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon_in_app.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.accessibility_new,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'TAM',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Transformation Accessibility Mass',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.95),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ผู้ช่วยอัจฉริยะเพื่อการเข้าถึง',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
