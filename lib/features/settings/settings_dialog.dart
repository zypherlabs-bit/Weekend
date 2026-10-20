import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../safety/safety_dialogs.dart';
import 'privacy_modes_dialog.dart';
import 'support_dialog.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/app_lock_service.dart';
import '../../services/notification_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../config/supabase_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

/// Weekend account settings: privacy toggles, biometric app lock,
/// account security (2FA / change password / sessions / delete).
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _pushNotifications = true;

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
    _loadPushSetting();
  }

  /// Read the stored push-notification preference.
  ///
  /// `user_settings.push_notifications_enabled` has existed since migration 001
  /// and had no reader, so this switch was hardcoded to `true` and reset on
  /// every open.
  Future<void> _loadPushSetting() async {
    final client = SupabaseConfig.client;
    if (client == null) return;

    final userId = SupabaseConfig.currentUserId;
    if (userId == 'me' || userId == 'unauthenticated') return;

    try {
      final rows = await client
          .from('user_settings')
          .select('push_notifications_enabled')
          .eq('user_id', userId)
          .limit(1);
      if (!mounted || rows.isEmpty) return;
      final stored = rows.first['push_notifications_enabled'];
      if (stored is bool && !_pushNotifications) {
        setState(() => _pushNotifications = stored);
      }
    } catch (_) {
      // A failed read leaves the optimistic default; the toggle still works and
      // the next open will re-read.
    }
  }

  /// Persist the push-notification preference.
  ///
  /// Turning notifications ON asks for the OS permission first. `requestPermission`
  /// had no caller anywhere in `lib/`, so the permission was never actually
  /// requested and the switch only changed a local field. If the user declines
  /// at the OS prompt the switch snaps back, because leaving it on while
  /// nothing is delivered is the more misleading state.
  Future<void> _setPushNotifications(bool value) async {
    if (value && !_pushNotifications) {
      try {
        await NotificationService().requestPermission();
      } catch (e) {
        debugPrint('Push permission request failed: ${e.runtimeType}');
      }
    }

    setState(() => _pushNotifications = value);

    final client = SupabaseConfig.client;
    if (client == null) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == 'me' || userId == 'unauthenticated') return;

    try {
      await client.from('user_settings').upsert({
        'user_id': userId,
        'push_notifications_enabled': value,
      }, onConflict: 'user_id');
    } catch (e) {
      if (!mounted) return;
      // Roll the switch back: reporting a saved setting that was not saved is
      // how a user ends up believing alerts are on when they are not.
      setState(() => _pushNotifications = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That preference could not be saved. Try again.'),
        ),
      );
    }
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
      SnackBar(
        content: Text(
          result.message.isEmpty ? 'Passkey removed' : result.message,
        ),
      ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
      Color? titleColor,
      Color? iconColor,
    }) {
      return ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: titleColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
        trailing: trailing,
        onTap: onTap,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: WeekendGlass.strong(
          padding: EdgeInsets.zero,
          radius: WeekendRadius.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Settings',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    WeekendGlassIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Close settings',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AppearanceSelector(),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        secondary: Icon(
                          Icons.notifications_active_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          'Push Notifications',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _pushNotifications
                              ? 'Match and message alerts are on'
                              : 'You will only be alerted while the app is open',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                        value: _pushNotifications,
                        onChanged: (value) => _setPushNotifications(value),
                      ),
                      if (_isLoadingBiometric)
                        tile(
                          icon: Icons.fingerprint_rounded,
                          title: 'Biometric App Lock',
                          subtitle: 'Checking this device…',
                          trailing: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        SwitchListTile(
                          secondary: Icon(
                            Icons.fingerprint_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            'Biometric App Lock',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Use fingerprint or face to unlock the app',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                          value: _biometricLock,
                          onChanged: _toggleBiometricLock,
                        ),
                      tile(
                        icon: Icons.shield_outlined,
                        title: 'Security & 2FA',
                        subtitle: _isLoadingMfa
                            ? 'Checking…'
                            : (_isMfaEnabled
                                  ? 'Two-factor authentication is ON'
                                  : 'Two-factor authentication is OFF'),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: _openSecurity,
                      ),
                      tile(
                        icon: Icons.key_rounded,
                        title: 'Passkeys',
                        subtitle: _isLoadingPasskeys
                            ? 'Checking…'
                            : (_passkeyCount == 0
                                  ? 'Sign in without a password using your '
                                        'fingerprint, face or device PIN'
                                  : '$_passkeyCount passkey'
                                        '${_passkeyCount == 1 ? '' : 's'} on this '
                                        'account'),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: _isLoadingPasskeys ? null : _openPasskeys,
                      ),
                      tile(
                        icon: Icons.password_rounded,
                        title: 'Change password',
                        subtitle: 'Email a reset link',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: _changePassword,
                      ),
                      tile(
                        icon: Icons.language_rounded,
                        title: 'Language',
                        subtitle: 'English (more languages planned)',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'English is the supported language in this '
                                'release.',
                              ),
                            ),
                          );
                        },
                      ),
                      tile(
                        icon: Icons.visibility_off_outlined,
                        title: 'Privacy',
                        subtitle:
                            'Incognito, snooze, away note, travel mode '
                            'and online status',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (dialogContext) =>
                                const PrivacyModesDialog(),
                          );
                        },
                      ),
                      tile(
                        icon: Icons.support_agent_rounded,
                        title: 'Support',
                        subtitle: 'Questions, safety concerns and scam reports',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (dialogContext) => const SupportDialog(),
                          );
                        },
                      ),
                      tile(
                        icon: Icons.location_on_outlined,
                        title: 'Location settings',
                        subtitle: 'Discovery radius and location sharing',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          if (context.mounted) {
                            context.push('/location-settings');
                          }
                        },
                      ),
                      tile(
                        icon: Icons.health_and_safety_outlined,
                        title: 'Safety Center',
                        subtitle: 'Blocking, reporting and safety tools',
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => const SafetyCenterDialog(),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Divider(
                          color: theme.colorScheme.error.withValues(
                            alpha: 0.22,
                          ),
                        ),
                      ),
                      tile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Delete Account',
                        titleColor: theme.colorScheme.error,
                        iconColor: theme.colorScheme.error,
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.error,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showDeleteAccountDialog(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext dialogContext) {
    final messenger = ScaffoldMessenger.of(dialogContext);
    // Held outside the builder so it survives the StatefulBuilder rebuilds
    // below and is not recreated (and cleared) on every keystroke.
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: dialogContext,
      builder: (context) {
        var deleting = false;

        /// Shared by the button and the keyboard "done" action, so both paths
        /// validate first and both report a failure the same way.
        Future<void> confirmDelete(StateSetter setState) async {
          if (deleting) return;
          if (!(formKey.currentState?.validate() ?? false)) return;

          setState(() => deleting = true);
          final deleted = await ref
              .read(authStateProvider.notifier)
              .deleteAccount(password: passwordController.text);

          if (!context.mounted) return;

          if (deleted) {
            Navigator.pop(context);
            if (dialogContext.mounted) {
              dialogContext.go('/onboarding');
            }
            return;
          }

          // Stay on the dialog so the user can correct a mistyped password
          // rather than being dropped back into settings with no idea what
          // happened.
          setState(() => deleting = false);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                ref.read(authStateProvider).error ??
                    'Account deletion failed. Try again.',
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setState) => WeekendGlassDialog(
            title: 'Delete Account',
            destructive: true,
            icon: Icons.delete_forever_outlined,
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes your profile, photos, matches '
                    'and every message you have sent. This action cannot be undone.',
                  ),
                  const SizedBox(height: 16),
                  // Deletion is irreversible, and a live session token is
                  // routinely long-lived and left in a device cache, so the
                  // server requires the account password as proof before it
                  // will act. Without this field the request is rejected.
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    enabled: !deleting,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm your password',
                      helperText: 'Required to delete your account',
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Enter your password to confirm.'
                        : null,
                    onFieldSubmitted: (_) => confirmDelete(setState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: deleting ? null : () => confirmDelete(setState),
                child: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Delete',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Day / Night / Auto appearance selector.
///
/// The three cards are real controls over [themeModeProvider]; the selected
/// value is persisted before the next frame.  `Auto` maps to
/// `ThemeMode.system`, so it follows the device without resetting the choice.
class _AppearanceSelector extends ConsumerWidget {
  const _AppearanceSelector();

  static const _options = <(ThemeMode, String, String, IconData)>[
    (ThemeMode.light, 'Day', 'Always light', Icons.wb_sunny_rounded),
    (ThemeMode.dark, 'Night', 'Always dark', Icons.nightlight_round),
    (ThemeMode.system, 'Auto', 'Follows device', Icons.phone_android_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 3),
          Text(
            'Choose how Weekend looks. Auto follows your device.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var index = 0; index < _options.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _AppearanceCard(
                    mode: _options[index].$1,
                    label: _options[index].$2,
                    description: _options[index].$3,
                    icon: _options[index].$4,
                    selected: current == _options[index].$1,
                    onTap: () => ref
                        .read(themeModeProvider.notifier)
                        .set(_options[index].$1),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceCard({
    required this.mode,
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label appearance, $description',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(WeekendRadius.md),
          onTap: onTap,
          child: AnimatedContainer(
            duration: WeekendMotion.standard,
            curve: WeekendMotion.curve,
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WeekendRadius.md),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.22),
                        AppTheme.violet.withValues(alpha: 0.16),
                      ],
                    )
                  : null,
              color: selected
                  ? null
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.045)
                        : Colors.black.withValues(alpha: 0.025)),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.72)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.18)
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.055,
                              ),
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
