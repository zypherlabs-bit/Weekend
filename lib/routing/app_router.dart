import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/vpn_security_provider.dart';
import '../models/models.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/confirm_email_screen.dart';
import '../features/auth/mfa_challenge_screen.dart';
import '../features/auth/mfa_enrollment_screen.dart';
import '../features/auth/security_setup_screen.dart';
import '../features/auth/signup_wizard_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_viewer_screen.dart';

import '../features/profile/edit_profile_screen.dart';
import '../features/discovery/explore_screen.dart';
import '../features/discovery/preferred_match_screen.dart';

import '../features/discovery/location_permission_screen.dart';

import '../features/discovery/location_settings_screen.dart';
import '../features/discovery/search_screen.dart';
import '../features/likes/likes_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/chat/match_conversation_screen.dart';
import '../features/qr/qr.dart';
import '../features/safety/safety_center_screen.dart';
import '../features/security/vpn_blocked_screen.dart';
import '../widgets/weekend_design_system.dart';
import '../theme/app_theme.dart';
import 'vpn_route_guard.dart';

/// Bridges the Riverpod auth and VPN security state into GoRouter's refresh
/// hook.
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
    ref.listen<VpnSecurityState>(vpnSecurityProvider, (previous, next) {
      if (previous?.routingFingerprint == next.routingFingerprint) return;
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
      final isSignup = location == '/signup';
      final isMfa = location == '/mfa-challenge';
      final isConfirmEmail = location == '/confirm-email';
      final isPersonalDetails = location == '/edit-profile';
      final isSecuritySetup = location == '/security-setup';

      // A pending 2FA step-up stays on the challenge screen; nowhere else.
      if (authState.needsMfaChallenge && !isMfa) return '/mfa-challenge';
      if (!authState.needsMfaChallenge && isMfa) {
        return isAuthenticated ? '/home' : '/auth';
      }

      // Screens a visitor may legitimately see with no session. The splash is
      // deliberately NOT one of them: it must hand off to onboarding once the
      // session check finishes, otherwise the app would sit on it forever.
      final isGuestScreen =
          isOnboarding || isAuth || isSignup || isConfirmEmail;
      final isEntryScreen = isSplash || isGuestScreen;

      // Legacy links (?mode=signup) open the dedicated sign-up wizard.
      if (isAuth && state.uri.queryParameters['mode'] == 'signup') {
        return '/signup?from=onboarding';
      }

      // While the session is being restored, keep the user on the splash.
      // Guest screens may also stay put: an in-progress sign-in/sign-up flips
      // `isLoading` on the very screen the user is typing on, and forcing it
      // through splash (then onward to onboarding) was the defect that
      // bounced people back to the start of the flow.
      if (isLoading) {
        final canHoldProgress = isSplash || isGuestScreen;
        return canHoldProgress ? null : '/';
      }

      if (!isAuthenticated) {
        if (isGuestScreen || isMfa) return null;
        return '/onboarding';
      }

      // Central security guard.  Every authenticated non-public destination
      // is protected by default; only this redirect decides whether it can be
      // shown.  `onBlocked` remembers the last protected location so a
      // successful re-check can restore it.
      final vpnState = ref.read(vpnSecurityProvider);
      final accessConfirmed = vpnState.accessConfirmed;
      final vpnTarget = vpnRedirectTarget(
        location: state.uri.toString(),
        blocksProtectedContent: vpnState.blocksProtectedContent,
        accessConfirmed: accessConfirmed,
        isAuthenticated: isAuthenticated,
        restoreLocation: vpnState.restoreLocation,
        onBlocked: (location) {
          ref
              .read(vpnSecurityProvider.notifier)
              .rememberProtectedLocation(location);
        },
      );
      if (vpnTarget != null) return vpnTarget;

      // Authenticated users with an incomplete profile finish Personal
      // Details first (except anonymous guests, who skip onboarding).
      // `/security-setup` is exempt for the same reason `/edit-profile` is:
      // every brand-new account has `needsProfileSetup` true, so without the
      // exemption the passkey/biometric offer would be skipped on arrival -
      // exactly the step this screen exists to show.
      if (authState.needsProfileSetup &&
          !isPersonalDetails &&
          !isSecuritySetup &&
          !isMfa) {
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
        // Sign-in only: email/password or a passkey. Sign-up lives on its own
        // Tinder-style wizard at /signup.
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => SignupWizardScreen(
          // Where the first step's back arrow returns: onboarding's
          // "Get Started" vs. the sign-in screen's "Sign up" link.
          returnTo: state.uri.queryParameters['from'] == 'auth'
              ? '/auth'
              : '/onboarding',
        ),
      ),

      GoRoute(
        path: '/confirm-email',
        builder: (context, state) => const ConfirmEmailScreen(),
      ),

      // Post-signup security setup. Deliberately NOT a guest screen: a
      // passkey can only be registered for an existing session, and the
      // redirect below keeps it behind authentication.
      GoRoute(
        path: '/security-setup',
        builder: (context, state) => const SecuritySetupScreen(),
      ),

      GoRoute(
        path: '/mfa-challenge',
        builder: (context, state) => const MfaChallengeScreen(),
      ),

      GoRoute(
        path: '/mfa-enrollment',
        builder: (context, state) => const MfaEnrollmentScreen(),
      ),

      // Security blocker. Deliberately a route rather than an overlay: a
      // restored deep link, a notification tap and an in-app push all go
      // through the same guard and cannot skip it.
      GoRoute(
        path: '/vpn-blocked',
        builder: (context, state) => const VpnBlockedScreen(),
      ),

      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),

      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'viewer',
            builder: (context, state) {
              final index =
                  int.tryParse(state.uri.queryParameters['index'] ?? '') ?? 0;
              return ProfileViewerScreen(initialIndex: index);
            },
          ),
        ],
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
        path: '/preferred-match',
        builder: (context, state) => const PreferredMatchScreen(),
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
        path: '/open-source',
        builder: (context, state) => const AboutOpenSourceScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/safety-center',
        builder: (context, state) => const SafetyCenterScreen(),
      ),

      // Interaction surfaces. Both were absent entirely: the `notifications`
      // table was written by the database but never read back, and inbound
      // likes were never queried at all.
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationCentreScreen(),
      ),

      GoRoute(path: '/likes', builder: (context, state) => const LikesScreen()),

      // Deep-linkable conversation. `ChatScreen` needs a populated MatchItem;
      // this route resolves the id and hands off, so a notification tap, a
      // shared link and an in-app tap all land in the same place.
      GoRoute(
        path: '/chat/:matchId',
        builder: (context, state) => MatchConversationScreen(
          matchId: state.pathParameters['matchId'] ?? '',
        ),
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WeekendAtmosphere(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: WeekendMotion.gentle,
                curve: WeekendMotion.curve,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.96 + (0.04 * value),
                    child: child,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WeekendLogo(
                      size: 126,
                      showWordmark: true,
                      tagline: 'Make every weekend brighter.',
                      glow: true,
                    ),
                    const SizedBox(height: 42),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Preparing your weekend…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
