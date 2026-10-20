import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncValue;
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/intro_video_player.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    try {
      await ref
          .read(authStateProvider.notifier)
          .signInWithEmail(email, password);
      if (!mounted) return;
      final authState = ref.read(authStateProvider);
      if (authState.needsMfaChallenge) {
        context.go('/mfa-challenge');
      } else if (authState.isAuthenticated) {
        // First-time accounts go to Personal Details, an existing complete
        // profile goes home.
        context.go(authState.needsProfileSetup ? '/edit-profile' : '/home');
      }
      // Anything else is a failed attempt: the error stays in state and
      // renders inline. Never navigate on failure — bouncing through splash
      // to onboarding was the old "sent back to sign-up" defect.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _passkeySignIn() async {
    setState(() => _submitting = true);
    try {
      await ref.read(authStateProvider.notifier).signInWithPasskey();
      if (!mounted) return;
      final authState = ref.read(authStateProvider);
      if (authState.needsMfaChallenge) {
        context.go('/mfa-challenge');
      } else if (authState.isAuthenticated) {
        context.go(authState.needsProfileSetup ? '/edit-profile' : '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // The clips run full-bleed behind the whole form rather than sitting in a
      // 180px panel above it. The form is a glass card over the footage, and
      // the scrim keeps it readable on any frame.
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _IntroCarousel(),
          const _FormScrim(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const WeekendLogo(size: 40, glow: false),
                        const SizedBox(width: 9),
                        Text(
                          'Weekend',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            shadows: const [
                              Shadow(color: Color(0x66000000), blurRadius: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    WeekendGlass.strong(
                      radius: WeekendRadius.xl,
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in with your email and password or a passkey',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(
                                    () =>
                                        _obscurePassword = !_obscurePassword,
                                  );
                                },
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 '
                                    'characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          if (authState.error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius:
                                    BorderRadius.circular(WeekendRadius.sm),
                                border: Border.all(
                                  color: errorColor.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                authState.error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          WeekendGlassButton(
                            label: 'Sign In',
                            icon: Icons.login_rounded,
                            loading: _submitting,
                            onPressed:
                                (authState.isLoading || _submitting)
                                    ? null
                                    : _submit,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              // A stale error must not follow the user across
                              // screens.
                              ref
                                  .read(authStateProvider.notifier)
                                  .dismissError();
                              context.go('/signup?from=auth');
                            },
                            child: const Text(
                              "Don't have an account? Sign up",
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'or',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed:
                                (authState.isLoading || _submitting)
                                    ? null
                                    : _passkeySignIn,
                            icon: const Icon(Icons.fingerprint, size: 21),
                            label: const Text('Sign in with passkey'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Private by design',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cycles the three intro clips above the sign-in form.
///
/// Design notes:
/// * **One player at a time.** Only the current index is `active`, so the
///   other two pause and drop their frame callbacks. Three simultaneous
///   decoders on the auth screen would burn battery for nothing.
/// * **Auto-advance is timer-driven, not video-driven.** The clips have
///   different durations, so advancing on a fixed tick is predictable and
///   keeps the cycle moving even if a clip fails to report its length.
/// * **Suppressed for reduced motion.** `MediaQuery.disableAnimations` also
///   stops the auto-advance: a user who has asked for less motion should not
///   be shown a slideshow they cannot also pause.
/// * **Non-interactive.** The form is the point of this screen; the carousel
///   is atmosphere and must never swallow a tap meant for an input. It is
///   painted behind the form rather than above it, so every tap lands on the
///   form.
class _IntroCarousel extends StatefulWidget {
  const _IntroCarousel();

  @override
  State<_IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<_IntroCarousel> {
  int _index = 0;
  static const Duration _tick = Duration(seconds: 5);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Timer? _timer;

  void _startTimer() {
    _timer?.cancel();
    // Do not auto-advance when the user has asked for reduced motion.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !mounted) return;
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % kIntroClips.length);
    });
  }

  @override
  void initState() {
    super.initState();
    // Deferred: initState runs before the first build, and the media query
    // (which decides whether to auto-advance) is not readable until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTimer());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cross-fade between clips so a hard cut does not flash black.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: IntroVideoPlayer(
            key: ValueKey<int>(_index),
            clip: kIntroClips[_index],
            active: true,
            autoplay: true,
            // Full bleed: square corners, clip fills the whole screen.
            borderRadius: 0,
          ),
        ),
      ],
    );
  }
}

/// Darkens the full-bleed carousel so the sign-in form stays readable on top
/// of it. Heavier than the onboarding scrim because this screen has dense
/// input fields rather than three lines of copy.
class _FormScrim extends StatelessWidget {
  const _FormScrim();

  @override
  Widget build(BuildContext context) {
    // IgnorePointer is required, not cosmetic: RenderDecoratedBox reports
    // hitTestSelf == true, so without this the scrim would sit over the form
    // and eat taps meant for the text fields and buttons underneath it.
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x99000000), Color(0xCC000000), Color(0xF2000000)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}
