import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../safety/safety_dialogs.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/app_lock_service.dart';
import '../../providers/auth_provider.dart';
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
  bool _togglingBiometric = false;
  bool _isMfaEnabled = false;
  bool _isLoadingMfa = true;

  /// Passkeys registered to the signed-in account.
  bool _isLoadingPasskeys = true;
  int _passkeyCount = 0;

  final _authRepository = AuthRepository();

  @override
  void initState() {
    super.initState();
    _loadBiometricSetting();
    _loadMfaStatus();
    _loadPasskeys();
  }

  /// Read how many passkeys the account has.
  ///
  /// Failure is not surfaced: "0 passkeys" simply shows the add affordance,
  /// and a transient network error should not block the settings sheet.
  Future<void> _loadPasskeys() async {
    try {
      final passkeys = await _authRepository.listPasskeys();
      if (mounted) {
        setState(() {
          _passkeyCount = passkeys.length;
          _isLoadingPasskeys = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPasskeys = false);
    }
  }

  /// Offer to register a new passkey, or remove an existing one.
  Future<void> _openPasskeys() async {
    if (_passkeyCount == 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add a passkey?'),
          content: const Text(
            'Your phone will ask for your fingerprint, face or device PIN. '
            'The passkey is stored in this device\'s secure hardware and can '
            'sign you in without a password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final ok = await ref
          .read(authStateProvider.notifier)
          .registerPasskey(friendlyName: 'Weekend on this device');
      if (!mounted) return;
      await _loadPasskeys();
      // Re-checked after the second await: the state may have been disposed
      // while the passkey list was being refetched.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Passkey added. You can now sign in without a password.'
                // The notifier already set a user-safe message; reuse it.
                : ref.read(authStateProvider).error ??
                      'Could not add a passkey.',
          ),
        ),
      );
      return;
    }

    // Existing passkeys: offer removal of the most recent one.
    final passkeys = await _authRepository.listPasskeys();
    if (!mounted || passkeys.isEmpty) return;
    final target = passkeys.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove passkey?'),
        content: Text(
          'This removes "${target.friendlyName ?? 'Passkey'}" from your '
          'account. You can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await _authRepository.deletePasskey(target.id);
    if (!mounted) return;
    await _loadPasskeys();
    // Re-checked after the second await: the state may have been disposed
    // while the passkey list was being refetched.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message.isEmpty ? 'Passkey removed' : result.message)),
    );
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

  /// Turning the app lock on/off.
  ///
  /// Enabling requires a real prompt FIRST: the flag is only persisted after a
  /// successful authentication, so a user can never end up locked out by a
  /// toggle they could not satisfy. Disabling writes through
  /// [AppLockService] so the live lock state stays in sync with storage.
  Future<void> _toggleBiometricLock(bool value) async {
    if (_togglingBiometric) return;
    setState(() => _togglingBiometric = true);
    try {
      if (value) {
        final result = await BiometricAuthService.authenticate(
          localizedReason: 'Confirm to enable Weekend app lock',
          stickyAuth: true,
        );
        if (!result.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.errorMessage ??
                      'Could not enable app lock. Please try again.',
                ),
              ),
            );
          }
          // The switch stays where the user last saw it: unchanged.
          await _loadBiometricSetting();
          return;
        }
        await AppLockService.instance.setLockEnabled(true);
        if (mounted) setState(() => _biometricLock = true);
      } else {
        await AppLockService.instance.setLockEnabled(false);
        if (mounted) setState(() => _biometricLock = false);
      }
    } catch (e) {
      await _loadBiometricSetting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingBiometric = false);
    }
  }


  Future<void> _changePassword() async {
    final email = SupabaseConfig.client?.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email on this account â€” cannot send reset link.'),
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
                    'Checkingâ€¦',
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
              'Passkeys',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _isLoadingPasskeys
                  ? 'Checkingâ€¦'
                  : (_passkeyCount == 0
                        ? 'Sign in without a password using your fingerprint, '
                              'face or device PIN'
                        : '$_passkeyCount passkey${_passkeyCount == 1 ? '' : 's'} '
                              'on this account'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            trailing: const Icon(
              Icons.key_rounded,
              color: Colors.white60,
            ),
            onTap: _isLoadingPasskeys ? null : _openPasskeys,
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
            subtitle: const Text(
              'English (more languages planned)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('English is the supported language in this release.'),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Privacy', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Discovery radius and visibility in Location settings',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white60,
            ),
            onTap: () {
              Navigator.pop(context);
              if (context.mounted) context.push('/location-settings');
            },
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
    final messenger = ScaffoldMessenger.of(dialogContext);
    showDialog(
      context: dialogContext,
      builder: (context) {
        var deleting = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
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
                onPressed: deleting ? null : () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: deleting
                    ? null
                    : () async {
                        setState(() => deleting = true);
                        final deleted = await ref
                            .read(authStateProvider.notifier)
                            .deleteAccount();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (deleted) {
                          if (dialogContext.mounted) {
                            dialogContext.go('/onboarding');
                          }
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ref.read(authStateProvider).error ??
                                    'Account deletion failed. Try again.',
                              ),
                            ),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
    );
  }
}
