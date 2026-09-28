import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide AsyncValue;
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/intro_video_player.dart';

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
        context.go(
          authState.needsProfileSetup ? '/edit-profile' : '/home',
        );
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
        context.go(
          authState.needsProfileSetup ? '/edit-profile' : '/home',
        );
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
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                // The same three intro clips shown during onboarding, cycling
                // quietly above the form. Bounded to 180px and non-
                // interactive: the form is the purpose of this screen, and a
                // full-bleed player here would fight the keyboard.
                SizedBox(
                  height: 180,
                  child: _IntroCarousel(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome Back',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with your email and password or a passkey',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Sign-in methods: email/password below, passkey at the bottom.
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Email', Icons.email_outlined),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    'Password',
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white60,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (authState.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      authState.error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed:
                        (authState.isLoading || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4B72),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    // A stale error must not follow the user across screens.
                    ref.read(authStateProvider.notifier).dismissError();
                    context.go('/signup?from=auth');
                  },
                  child: const Text(
                    "Don't have an account? Sign up",
                    style: TextStyle(
                      color: Color(0xFFFF9966),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: (authState.isLoading || _submitting)
                      ? null
                      : _passkeySignIn,
                  icon: const Icon(Icons.fingerprint, color: Color(0xFFFF9966)),
                  label: const Text(
                    'Sign in with Passkey',
                    style: TextStyle(
                      color: Color(0xFFFF9966),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFFF9966)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      prefixIcon: Icon(icon, color: Colors.white60),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1C162E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),

      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF4B72)),
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
///   is atmosphere and must never swallow a tap meant for an input.
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
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
              borderRadius: 20,
            ),
          ),
          // A scrim keeps the bottom scrim from competing with the form
          // text below it, and gives the rounded corners something to sit on.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.25),
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

