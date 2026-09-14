import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/biometric_auth_service.dart';

class BiometricLockScreen extends ConsumerStatefulWidget {
  final VoidCallback? onAuthenticated;
  const BiometricLockScreen({super.key, this.onAuthenticated});
  @override
  ConsumerState<BiometricLockScreen> createState() =>
      _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _isAuthenticating = false;
  String? _errorMessage;
  BiometricType? _biometricType;
  @override
  void initState() {
    super.initState();
    _loadBiometricType();
    _authenticate();
  }

  Future<void> _loadBiometricType() async {
    final type = await BiometricAuthService.getEnabledBiometricType();
    if (mounted) {
      setState(() {
        _biometricType = type;
      });
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });
    final biometricTypeLabel = _getBiometricTypeLabel(_biometricType);
    final result = await BiometricAuthService.authenticate(
      localizedReason: 'Use $biometricTypeLabel to unlock Weekend',
      useErrorDialogs: true,
      stickyAuth: true,
    );
    if (!mounted) return;
    if (result.success) {
      widget.onAuthenticated?.call();
      context.go('/home');
    } else {
      setState(() {
        _isAuthenticating = false;
        _errorMessage = _getErrorMessage(result.errorCode);
      });
      if (result.errorCode == BiometricAuthErrorCode.lockedOut ||
          result.errorCode == BiometricAuthErrorCode.permanentlyLockedOut) {
        _showDeviceCredentialFallback();
      }
    }
  }

  String _getBiometricTypeLabel(BiometricType? type) {
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
        return 'biometric authentication';
    }
  }

  String _getErrorMessage(BiometricAuthErrorCode? errorCode) {
    switch (errorCode) {
      case BiometricAuthErrorCode.notAvailable:
        return 'Biometric authentication is not available on this device';
      case BiometricAuthErrorCode.notEnrolled:
        return 'No biometrics enrolled. Please set up biometrics in device settings';
      case BiometricAuthErrorCode.lockedOut:
        return 'Biometric locked out. Try again later or use device credentials';
      case BiometricAuthErrorCode.permanentlyLockedOut:
        return 'Biometric permanently locked out. Use device credentials';
      case BiometricAuthErrorCode.userCancel:
        return 'Authentication cancelled';
      case BiometricAuthErrorCode.systemCancel:
        return 'Authentication cancelled by system';
      case BiometricAuthErrorCode.passcodeNotSet:
        return 'Device passcode not set. Please set a passcode in device settings';
      default:
        return 'Authentication failed. Please try again';
    }
  }

  Future<void> _showDeviceCredentialFallback() async {
    final result = await BiometricAuthService.authenticate(
      localizedReason: 'Use your device credentials to unlock Weekend',
      useErrorDialogs: true,
      stickyAuth: true,
      sensitiveTransaction: false,
    );
    if (!mounted) return;
    if (result.success) {
      widget.onAuthenticated?.call();
      context.go('/home');
    } else {
      setState(() {
        _errorMessage = _getErrorMessage(result.errorCode);
      });
    }
  }

  void _retry() {
    _authenticate();
  }

  void _disableBiometricLock() async {
    await BiometricAuthService.disableBiometric();
    if (mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
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
                      color: const Color(0xFFFF4B72).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  _getBiometricIcon(_biometricType),
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Unlock Weekend',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _biometricType != null
                    ? 'Use ${_getBiometricTypeLabel(_biometricType)} to continue'
                    : 'Authenticate to access your account',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_isAuthenticating)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B72)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _retry,
                        icon: Icon(_getBiometricIcon(_biometricType), size: 22),
                        label: Text(
                          'Unlock with ${_getBiometricTypeLabel(_biometricType).capitalize()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _disableBiometricLock,
                      child: Text(
                        'Disable Biometric Lock',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getBiometricIcon(BiometricType? type) {
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
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
