import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../config/supabase_config.dart';
import '../models/models.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/confirm_email_screen.dart';
import '../features/auth/mfa_challenge_screen.dart';
import '../features/auth/mfa_enrollment_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';

import '../features/profile/edit_profile_screen.dart';
import '../features/discovery/explore_screen.dart';

import '../features/discovery/location_permission_screen.dart';

import '../features/discovery/location_settings_screen.dart';
import '../features/qr/qr.dart';
import '../features/safety/safety_center_screen.dart';

/// Bridges the Riverpod auth state into GoRouter's refresh hook.
///
/// Only routing-relevant transitions notify; the redirect itself always reads
/// the current state with `ref.read`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<WeekendAuthState>(authStateProvider, (previous, next) {
      if (previous?.isAuthenticated == next.isAuthenticated &&
          previous?.isLoading == next.isLoading &&
          previous?.needsProfileSetup == next.needsProfileSetup &&
          previous?.needsMfaChallenge == next.needsMfaChallenge &&
          previous?.awaitingEmailConfirmation ==
              next.awaitingEmailConfirmation) {
        return;
      }
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // The router is built ONCE. Previously this provider used
  // `ref.watch(authStateProvider)`, so every auth-state emission disposed the
  // provider and constructed a brand-new GoRouter. A fresh GoRouter starts at
  // `initialLocation: '/'`, which threw the user back through splash → entry
  // screens again after signup and produced the repeated screens. Feeding the
  // state in through `refreshListenable` keeps one router instance for the app
  // lifetime: redirects re-run, navigation history is preserved.
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isAuthenticated = authState.isAuthenticated;
      final isLoading = authState.isLoading;

      final location = state.matchedLocation;
      final isSplash = location == '/';
      final isOnboarding = location == '/onboarding';
      final isAuth = location == '/auth';
      final isMfa = location == '/mfa-challenge';
      final isConfirmEmail = location == '/confirm-email';
      final isPersonalDetails = location == '/edit-profile';

      // While the session is being restored, keep the user on the splash.
      if (isLoading) return isSplash ? null : '/';

      // A pending 2FA step-up stays on the challenge screen; nowhere else.
      if (authState.needsMfaChallenge && !isMfa) return '/mfa-challenge';
      if (!authState.needsMfaChallenge && isMfa) {
        return isAuthenticated ? '/home' : '/auth';
      }

      // Screens a visitor may legitimately see with no session. The splash is
      // deliberately NOT one of them: it must hand off to onboarding once the
      // session check finishes, otherwise the app would sit on it forever.
      final isGuestScreen = isOnboarding || isAuth || isConfirmEmail;
      final isEntryScreen = isSplash || isGuestScreen;

      if (!isAuthenticated) {
        if (isGuestScreen || isMfa) return null;
        return '/onboarding';
      }

      // Authenticated users with an incomplete profile finish Personal
      // Details first (except anonymous guests, who skip onboarding).
      if (authState.needsProfileSetup && !isPersonalDetails && !isMfa) {
        return '/edit-profile';
      }

      // Authenticated users are redirected away from the entry screens.
      // Personal Details stays reachable after setup via explicit navigation.
      if (isEntryScreen && !authState.needsProfileSetup) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          // Arriving from onboarding means the visitor asked to create an
          // account, so open on "Create Account" instead of showing the
          // sign-in form first.
          startOnSignUp: state.uri.queryParameters['mode'] == 'signup',
        ),
      ),

      GoRoute(
        path: '/confirm-email',
        builder: (context, state) => const ConfirmEmailScreen(),
      ),

      GoRoute(
        path: '/mfa-challenge',
        builder: (context, state) => const MfaChallengeScreen(),
      ),

      GoRoute(
        path: '/mfa-enrollment',
        builder: (context, state) => const MfaEnrollmentScreen(),
      ),

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
