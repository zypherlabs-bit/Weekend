import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';

import 'routing/app_router.dart';
import 'services/biometric_auth_service.dart';
import 'features/auth/biometric_lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // LIVE-ONLY: a release binary must never ship without live credentials.
  // Debug and test runs may start unconfigured — every backend call is
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
      );
    } catch (e) {
      debugPrint('Supabase initialization failed; running unconfigured: $e');
    }
  }
  runApp(const ProviderScope(child: WeekendApp()));
}

class WeekendApp extends ConsumerStatefulWidget {
  const WeekendApp({super.key});

  @override
  ConsumerState<WeekendApp> createState() => _WeekendAppState();
}

class _WeekendAppState extends ConsumerState<WeekendApp>
    with WidgetsBindingObserver {
  bool _needsBiometricUnlock = false;
  OverlayEntry? _biometricOverlay;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _needsBiometricUnlock = true;
        break;
    }
  }

  Future<void> _onAppResumed() async {
    final biometricEnabled = await BiometricAuthService.isBiometricEnabled();
    if (biometricEnabled && _needsBiometricUnlock) {
      _showBiometricLockScreen();
    }
    _needsBiometricUnlock = false;
  }

  void _showBiometricLockScreen() {
    _removeBiometricOverlay();
    _biometricOverlay = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: BiometricLockScreen(onAuthenticated: _removeBiometricOverlay),
      ),
    );
    if (mounted) {
      Overlay.of(context, rootOverlay: true).insert(_biometricOverlay!);
    }
  }

  void _removeBiometricOverlay() {
    _biometricOverlay?.remove();
    _biometricOverlay = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeBiometricOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Weekend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
