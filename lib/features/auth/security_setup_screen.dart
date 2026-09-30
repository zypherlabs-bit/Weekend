import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../services/biometric_auth_service.dart';

/// Post-signup security setup: the single place a new account is offered a
/// passkey and an app-lock.
///
/// This screen exists because finishing signup used to dump the user straight
/// onto the sign-in form, even though they had just created the account and
/// confirmed their email. There was no passkey or biometric prompt anywhere in
/// the signup journey - passkey registration was reachable only from the
/// settings dialog, long after signup.
///
/// It is skippable: the primary action finishes setup, the secondary action
/// walks away without blocking onboarding.
class SecuritySetupScreen extends ConsumerStatefulWidget {
  const SecuritySetupScreen({super.key});

  @override
  ConsumerState<SecuritySetupScreen> createState() =>
      _SecuritySetupScreenState();
}

class _SecuritySetupScreenState extends ConsumerState<SecuritySetupScreen> {
  static const Color _background = Color(0xFF130E20);
  static const Color _primary = Color(0xFFFF4B72);
  static const Color _accent = Color(0xFFFF9966);

  bool _loading = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _busy = false;
  String? _passkeyMessage;
  bool _passkeyIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricAuthService.isBiometricAvailable();
    final enabled = await BiometricAuthService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    setState(() => _busy = true);
    await BiometricAuthService.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = value;
      _busy = false;
    });
  }

  /// Register a passkey, reporting the real outcome on the card itself.
  ///
  /// A failure here is usually a device with no screen lock set up yet, or a
  /// Google Digital Asset Links problem on an unverified release build, so the
  /// message is shown inline and the user can still continue.
  Future<void> _addPasskey() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _passkeyMessage = null;
    });

    final ok = await ref
        .read(authStateProvider.notifier)
        .registerPasskey(friendlyName: 'Weekend on this device');

    if (!mounted) return;
    setState(() {
      _busy = false;
      _passkeyIsError = !ok;
      _passkeyMessage = ok
          ? 'Passkey added. You can sign in without your password.'
          : ref.read(authStateProvider).error ?? 'Could not add a passkey.';
    });
  }

  /// Finish setup and continue into the app. Never routes to `/auth`.
  void _continue() {
    final state = ref.read(authStateProvider);
    context.go(state.needsProfileSetup ? '/edit-profile' : '/home');
  }

  @override

  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final name = authState.user?.name ?? 'there';

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, _accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'You\'re all set',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Nice to meet you, $name. Set up a quick way to sign in '
                'before you start exploring.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 32),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: _primary),
                  ),
                )
              else ...[
                _PasskeyCard(
                  busy: _busy,
                  message: _passkeyMessage,
                  isError: _passkeyIsError,
                  onAdd: _addPasskey,
                ),
                const SizedBox(height: 16),
                _BiometricCard(
                  available: _biometricAvailable,
                  enabled: _biometricEnabled,
                  busy: _busy,
                  onChanged: _toggleBiometric,
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _busy ? null : _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _continue,
                child: const Text(
                  'I\'ll do this later',
                  style: TextStyle(color: _accent, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

class _PasskeyCard extends StatelessWidget {
  const _PasskeyCard({
    required this.busy,
    required this.message,
    required this.isError,
    required this.onAdd,
  });

  final bool busy;
  final String? message;
  final bool isError;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFFFF9966)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Passkey',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: busy ? null : onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4B72),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in with your fingerprint, face or device PIN. '
            'No password needed.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isError
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF7BD88F),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BiometricCard extends StatelessWidget {
  const _BiometricCard({
    required this.available,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool available;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      child: Row(
        children: [
          const Icon(Icons.face_retouching_natural, color: Color(0xFFFF9966)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App lock',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  available
                      ? 'Ask for biometrics when Weekend opens.'
                      : 'No biometrics are enrolled on this device.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (available && !busy) ? onChanged : null,
            activeThumbColor: const Color(0xFFFF4B72),
          ),
        ],
      ),
    );
  }
}
