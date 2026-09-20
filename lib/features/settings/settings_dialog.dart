import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../safety/safety_dialogs.dart';
import '../../services/biometric_auth_service.dart';
import '../../repositories/auth_repository.dart';
import '../../config/supabase_config.dart';

/// Weekend account settings: privacy toggles, biometric app lock,
/// account security (2FA / change password / sessions / delete).
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _pushNotifications = true;

  bool _darkMode = true;

  bool _biometricLock = false;

  bool _isLoadingBiometric = true;
  bool _isMfaEnabled = false;
  bool _isLoadingMfa = true;
  final _authRepository = AuthRepository();

  @override
  void initState() {
    super.initState();
    _loadBiometricSetting();
    _loadMfaStatus();
  }

  Future<void> _loadBiometricSetting() async {
    final enabled = await BiometricAuthService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricLock = enabled;
        _isLoadingBiometric = false;
      });
    }
  }

  Future<void> _loadMfaStatus() async {
    try {
      final enabled = await _authRepository.isMfaEnabled();
      if (mounted) {
        setState(() {
          _isMfaEnabled = enabled;
          _isLoadingMfa = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMfa = false);
      }
    }
  }

  Future<void> _toggleBiometricLock(bool value) async {
    if (value) {
      final result = await BiometricAuthService.authenticate(
        localizedReason: 'Enable biometric app lock',
        useErrorDialogs: true,
        stickyAuth: true,
      );
      if (result.success) {
        if (mounted) {
          setState(() => _biometricLock = true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Failed to enable biometric lock',
              ),
            ),
          );
        }
      }
    } else {
      await BiometricAuthService.disableBiometric();
      if (mounted) {
        setState(() => _biometricLock = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final email = SupabaseConfig.client?.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email on this account — cannot send reset link.'),
        ),
      );
      return;
    }
    try {
      await _authRepository.resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send reset email. Try again.')),
      );
    }
  }

  Future<void> _openSecurity() async {
    Navigator.pop(context);
    if (context.mounted) {
      context.push('/mfa-enrollment');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C162E),
      title: const Text('Settings', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          SwitchListTile(
            title: const Text(
              'Push Notifications',
              style: TextStyle(color: Colors.white),
            ),
            value: _pushNotifications,
            onChanged: (value) => setState(() => _pushNotifications = value),
            activeThumbColor: const Color(0xFFFF4B72),
          ),
          SwitchListTile(
            title: const Text(
              'Dark Mode',
              style: TextStyle(color: Colors.white),
            ),
            value: _darkMode,
            onChanged: (value) => setState(() => _darkMode = value),

            activeThumbColor: const Color(0xFFFF4B72),
          ),
          _isLoadingBiometric
              ? const ListTile(
                  title: Text(
                    'Biometric App Lock',
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF4B72),
                    ),
                  ),
                )
              : SwitchListTile(
                  title: const Text(
                    'Biometric App Lock',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Use fingerprint/face to unlock the app',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  value: _biometricLock,
                  onChanged: _toggleBiometricLock,
                  activeThumbColor: const Color(0xFFFF4B72),
                ),
          ListTile(
            title: const Text(
              'Security & 2FA',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: _isLoadingMfa
                ? const Text(
                    'Checking…',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                : Text(
                    _isMfaEnabled
                        ? 'Two-factor authentication is ON'
                        : 'Two-factor authentication is OFF',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: _openSecurity,
          ),
          ListTile(
            title: const Text(
              'Change password',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Email a reset link',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: _changePassword,
          ),
          ListTile(
            title: const Text(
              'Language',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Privacy', style: TextStyle(color: Colors.white)),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: () {},
          ),
          ListTile(
            title: const Text(
              'Safety Center',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => const SafetyCenterDialog(),
              );
            },
          ),
          ListTile(
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.red,
            ),
             onTap: () {
              Navigator.pop(context);
              _showDeleteAccountDialog(context);
            },
          ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Close',
            style: TextStyle(color: Color(0xFFFF4B72)),
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(BuildContext dialogContext) {
    showDialog(
      context: dialogContext,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.red),
        ),
        content: const Text(
          'This action cannot be undone. All your data will be permanently deleted.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle account deletion
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
