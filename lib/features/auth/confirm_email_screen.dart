import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';

/// Step between "Create Account" and Personal Details when the connected
/// Supabase project requires email confirmation
/// (`mailer_autoconfirm = false`).
///
/// This screen never marks an account as verified. It explains the real state
/// Supabase reported, offers a genuine re-send performed by Supabase, and lets
/// the user continue once the confirmation actually happened.
class ConfirmEmailScreen extends ConsumerStatefulWidget {
  const ConfirmEmailScreen({super.key});

  @override
  ConsumerState<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends ConsumerState<ConfirmEmailScreen> {
  bool _isResending = false;
  bool _isContinuing = false;

  /// Turn "I clicked the link" into a real session.
  ///
  /// This used to do `context.go('/auth')`, which dropped a user who had just
  /// created an account and confirmed their email onto the sign-in form and
  /// made them retype the password they had chosen seconds earlier. Now the
  /// credentials captured by the wizard are used directly and the user lands
  /// on the passkey/biometric setup step instead.
  Future<void> _continueAfterConfirmation() async {
    if (_isContinuing) return;
    setState(() => _isContinuing = true);

    final notifier = ref.read(authStateProvider.notifier);
    final ok = await notifier.completeSignupAndSignIn();

    if (!mounted) return;
    setState(() => _isContinuing = false);
    if (!ok) {
      // `completeSignupAndSignIn` already put a readable message on the state.
      final message =
          ref.read(authStateProvider).error ?? 'Could not continue. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
      return;
    }

    // A pending 2FA step-up owns the next screen; the redirect would send the
    // user there anyway, so do not fight it.
    if (ref.read(authStateProvider).needsMfaChallenge) return;

    context.go('/security-setup');
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    final message =
        await ref.read(authStateProvider.notifier).resendConfirmationEmail();
    if (!mounted) return;
    setState(() => _isResending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final email = authState.pendingEmail;
    final bodyStyle = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Confirm your email',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                (email == null || email.isEmpty)
                    ? 'Your account was created. Open the confirmation link '
                        'we sent to finish setting it up.'
                    : 'We sent a confirmation link to\n$email',
                style: bodyStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Step(
                      number: '1',
                      text: 'Open the email from Weekend and tap the '
                          'confirmation link.',
                    ),
                    SizedBox(height: 12),
                    _Step(
                      number: '2',
                      text: 'Come back to the app and sign in. Your account is '
                          'then confirmed and Personal Details opens.',
                    ),
                    SizedBox(height: 12),
                    _Step(
                      number: '3',
                      text: 'No email after a few minutes? Check spam, then '
                          'tap "Resend confirmation email".',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isResending ? null : _resend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: _isResending
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.onSurface,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          'Resend confirmation email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: (_isResending || _isContinuing)
                      ? null
                      : _continueAfterConfirmation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.tertiary,
                    side: BorderSide(color: Theme.of(context).colorScheme.tertiary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isContinuing
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.tertiary,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          "I've confirmed — continue",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/auth?mode=signup'),
                child: Text(
                  'Use a different email',
                  style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
