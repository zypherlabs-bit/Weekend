import 'package:flutter/material.dart';

import '../../services/app_lock_service.dart';
import '../../services/biometric_auth_service.dart';

/// Covers the whole app with an unlock prompt whenever
/// [AppLockService.isLocked] is true.
///
/// Design notes
/// ------------
/// * Rendered from `MaterialApp.builder`, so it is always inside the widget
///   tree and always above the navigator. The previous implementation tried to
///   insert an `OverlayEntry` from the widget ABOVE `MaterialApp`, where no
///   Overlay exists yet - the prompt therefore never appeared.
/// * It never navigates. The old lock screen called `context.go('/home')` on
///   success, which threw the user out of whatever they were doing. Unlocking
///   restores access to exactly the screen they left.
/// * A failed or cancelled attempt leaves the app locked and offers an explicit
///   retry. There is no timeout escape hatch.
/// * While locked the content underneath is not merely covered, it is taken out
/// /// of the tree, so nothing behind the lock screen can be reached or
///   interact with.
class BiometricLockGate extends StatefulWidget {
  final Widget? child;

  const BiometricLockGate({super.key, this.child});

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate> {
  bool _prompting = false;
  String? _error;
  BiometricType? _biometricType;

  @override
  void initState() {
    super.initState();
    _loadBiometricType();
    // Prompt as soon as the gate mounts while locked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _loadBiometricType() async {
    try {
      final type = await BiometricAuthService.getEnabledBiometricType();
      if (mounted) setState(() => _biometricType = type);
    } catch (_) {
      // A missing preference only affects the wording, never the security.
    }
  }

  Future<void> _authenticate() async {
    if (_prompting || !mounted) return;
    setState(() {
      _prompting = true;
      _error = null;
    });

    final label = _typeLabel(_biometricType);
    final result = await BiometricAuthService.authenticate(
      localizedReason: 'Use $label to unlock Weekend',
      stickyAuth: true,
    );
    if (!mounted) return;

    if (result.success) {
      // The ONLY way out of the locked state.
      AppLockService.instance.onAuthenticationSucceeded();
      setState(() => _prompting = false);
      return;
    }

    setState(() {
      _prompting = false;
      _error = _errorMessage(result.errorCode);
    });

    // A hardware lockout is not something the user can retry through, so the
    // device-credential sheet is offered automatically.
    if (result.errorCode == BiometricAuthErrorCode.lockedOut ||
        result.errorCode == BiometricAuthErrorCode.permanentlyLockedOut) {
      await _deviceCredentialFallback();
    }
  }

  Future<void> _deviceCredentialFallback() async {
    final result = await BiometricAuthService.authenticate(
      localizedReason: 'Use your device credentials to unlock Weekend',
      stickyAuth: true,
    );
    if (!mounted) return;
    if (result.success) {
      AppLockService.instance.onAuthenticationSucceeded();
      setState(() => _prompting = false);
    } else {
      setState(() {
        _prompting = false;
        _error = _errorMessage(result.errorCode);
      });
    }
  }

  Future<void> _disableLock() async {
    await AppLockService.instance.setLockEnabled(false);
    // setLockEnabled clears the locked flag; nothing else to do here. The user
    // stays exactly where they were.
  }

  String _typeLabel(BiometricType? type) {
    switch (type) {
      case BiometricType.fingerprint:
        return 'your fingerprint';
      case BiometricType.face:
        return 'face recognition';
      case BiometricType.iris:
        return 'iris scan';
      case BiometricType.strong:
        return 'biometric authentication';
      default:
        return 'biometric authentication or your device PIN';
    }
  }

  IconData _typeIcon(BiometricType? type) {
    switch (type) {
      case BiometricType.fingerprint:
        return Icons.fingerprint_rounded;
      case BiometricType.face:
        return Icons.face_rounded;
      case BiometricType.iris:
        return Icons.remove_red_eye_rounded;
      default:
        return Icons.lock_rounded;
    }
  }

  String _errorMessage(BiometricAuthErrorCode? code) {
    switch (code) {
      case BiometricAuthErrorCode.notAvailable:
        return 'Biometric authentication is not available on this device.';
      case BiometricAuthErrorCode.notEnrolled:
        return 'No biometrics are enrolled. Add one in your device settings, '
            'or use your device PIN.';
      case BiometricAuthErrorCode.lockedOut:
        return 'Too many attempts. Use your device PIN to unlock.';
      case BiometricAuthErrorCode.permanentlyLockedOut:
        return 'Biometrics are locked out. Use your device PIN to unlock.';
      case BiometricAuthErrorCode.userCancel:
      case BiometricAuthErrorCode.systemCancel:
        return 'Weekend is still locked. Authenticate to continue.';
      case BiometricAuthErrorCode.passcodeNotSet:
        return 'Set a device PIN, password or pattern to protect Weekend.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockService.instance.locked,
      builder: (context, isLocked, child) {
        if (!isLocked) {
          // Unlocked: render the app normally. `child` is the real subtree,
          // kept out of the tree entirely while locked so nothing behind the
          // prompt is reachable.
          return child ?? const SizedBox.shrink();
        }
        return _LockSurface(
          prompting: _prompting,
          error: _error,
          icon: _typeIcon(_biometricType),
          label: _typeLabel(_biometricType),
          onRetry: _authenticate,
          onDisable: _disableLock,
        );
      },
      child: widget.child,
    );
  }
}

class _LockSurface extends StatelessWidget {
  final bool prompting;
  final String? error;
  final IconData icon;
  final String label;
  final VoidCallback onRetry;
  final VoidCallback onDisable;

  const _LockSurface({
    required this.prompting,
    required this.error,
    required this.icon,
    required this.label,
    required this.onRetry,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Fully opaque: while locked, nothing of the app beneath is visible.
      color: const Color(0xFF130E20),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Weekend's own identity - no third-party branding.
              const Center(
                child: Icon(Icons.weekend_rounded, size: 56, color: Color(0xFFFF4B72)),
              ),
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4B72).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: const Color(0xFFFF4B72)),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Weekend is locked',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Authenticate to get back to what you were doing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              if (prompting)
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF4B72),
                  ),
                )
              else
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: Icon(icon, size: 22),
                    label: const Text(
                      'Unlock',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4B72),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: prompting ? null : onDisable,
                child: Text(
                  'Turn off app lock',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
