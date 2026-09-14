import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../config/supabase_config.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';

import '../features/profile/edit_profile_screen.dart';
import '../features/discovery/explore_screen.dart';

import '../features/discovery/location_permission_screen.dart';

import '../features/discovery/location_settings_screen.dart';
import '../features/qr/qr.dart';
import '../features/safety/safety_center_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final isLoading = authState.isLoading;

      final isSplash = state.matchedLocation == '/';

      final isOnboarding = state.matchedLocation == '/onboarding';
      final isAuth = state.matchedLocation == '/auth';

      // While the session is being restored, keep the user on the splash.
      if (isLoading) return isSplash ? null : '/';

      // Unauthenticated users may only be on the splash, onboarding or auth.
      if (!isAuthenticated && !isOnboarding && !isAuth) {
        return '/onboarding';
      }

      // Authenticated users are redirected away from the entry screens.
      if (isAuthenticated && (isOnboarding || isAuth || isSplash)) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),

      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),

      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),

      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),

      GoRoute(
        path: '/explore',
        builder: (context, state) => const ExploreScreen(),
      ),

      GoRoute(
        path: '/location-permission',
        builder: (context, state) => const LocationPermissionScreen(),
      ),

      GoRoute(
        path: '/location-settings',
        builder: (context, state) => const LocationSettingsScreen(),
      ),

      GoRoute(
        path: '/qr-invite',
        builder: (context, state) => const QRInviteScreen(),
      ),
      GoRoute(
        path: '/qr-scanner',
        builder: (context, state) => const QRScannerScreen(),
      ),
      GoRoute(
        path: '/safety-center',
        builder: (context, state) => const SafetyCenterScreen(),
      ),
    ],
  );
});

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // The splash simply observes the auth-state provider. Once

    // `isLoading` becomes false, GoRouter's redirect navigates to either
    // onboarding (unauthenticated) or home (authenticated). No manual

    // navigation here avoids redirect/race conflicts.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupabaseConfig.isConfigured
          ? const Color(0xFF130E20)
          : const Color(0xFF130E20),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _WeekendLogo(),
            const SizedBox(height: 24),

            const Text(
              'Weekend',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make every weekend brighter.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white60,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B72)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekendLogo extends StatelessWidget {
  const _WeekendLogo();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4B72), Color(0xFFFF9966)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4B72).withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.weekend_rounded, size: 60, color: Colors.white),
    );
  }
}
