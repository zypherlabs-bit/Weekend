import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'theme/app_theme.dart';

import 'routing/app_router.dart';
import 'providers/theme_provider.dart';
import 'services/app_lock_service.dart';
import 'features/auth/biometric_lock_gate.dart';
import 'features/security/vpn_security_gate.dart';
import 'widgets/weekend_design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Let the glass atmosphere run under the system bars; each screen already
  // uses SafeArea for tappable content.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // LIVE-ONLY: a release binary must never ship without live credentials.
  // Debug and test runs may start unconfigured - every backend call is
  // null-guarded and returns empty results (never fabricated data), which is
  // how the test suite runs without a backend.
  if (kReleaseMode && !SupabaseConfig.isConfigured) {
    throw StateError(SupabaseConfig.configError);
  }
  if (SupabaseConfig.isConfigured) {
    // LIVE-ONLY: never let a release binary silently run against placeholder
    // or loopback credentials. Release CI also fails before building when
    // SUPABASE_URL / SUPABASE_ANON_KEY secrets are missing or placeholders.
    assert(() {
      SupabaseConfig.assertLiveConfigured();
      return true;
    }());
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
        // `client.auth.passkey` (Supabase's native WebAuthn API) is a plain
        // field on GoTrueClient in gotrue >= 2.27 and needs no opt-in flag.
        //
        // The server side is configured for this project (verified live):
        //   Authentication -> Passkeys -> enabled
        //   webauthn_rp_id     = <project-ref>.supabase.co
        //   webauthn_rp_origin = https://<project-ref>.supabase.co
      );
    } catch (e) {
      debugPrint('Supabase initialization failed; running unconfigured: $e');
    }
  }

  // Start the app lock observer and read the persisted preference BEFORE the
  // first frame, so an app that was killed while unlocked still locks on the
  // next cold start.
  AppLockService.instance.attach();
  await AppLockService.instance.loadFromStorage();

  // Same reasoning for the theme: loaded before the first frame so the app
  // never paints once in the wrong brightness and then corrects itself.
  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(container: container, child: const WeekendApp()),
  );
}

class WeekendApp extends ConsumerStatefulWidget {
  const WeekendApp({super.key});

  @override
  ConsumerState<WeekendApp> createState() => _WeekendAppState();
}

class _WeekendAppState extends ConsumerState<WeekendApp> {
  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Day / Night / Auto are persisted before the first frame; Auto is a
    // genuine ThemeMode.system, not a hardcoded brightness.
    final themeMode = ref.watch(themeModeProvider);
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => systemBrightness,
    };
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: effectiveBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: effectiveBrightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: effectiveBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);

    return MaterialApp.router(
      title: 'Weekend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: WeekendMotion.standard,
      themeAnimationCurve: WeekendMotion.curve,
      routerConfig: router,
      // Both gates live INSIDE the MaterialApp, so they are real widgets in
      // the tree rather than OverlayEntries inserted above the app.  The VPN
      // gate wraps the biometric gate so a resume check covers whatever was
      // last visible, including the lock screen.
      builder: (context, child) => WeekendAtmosphere(
        child: VpnSecurityGate(child: BiometricLockGate(child: child)),
      ),
    );
  }
}
