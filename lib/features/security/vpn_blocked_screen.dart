import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/vpn_security_provider.dart';
import '../../services/vpn_security_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

/// The only destination reachable while protected content is blocked.
///
/// The router enforces the block; this screen exists to explain it, show live
/// state and offer a deliberate re-check.  It never offers a "continue anyway"
/// action, because that would defeat the policy.
class VpnBlockedScreen extends ConsumerWidget {
  const VpnBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnSecurityProvider);
    final presentation = _VpnPresentation.from(state.status);
    final theme = Theme.of(context);

    return PopScope(
      // Back must not restore a protected route or the last task screenshot.
      // The system's own back gesture leaves the app; the in-app back stack is
      // never allowed to expose content.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: WeekendAtmosphere(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WeekendLogo(size: 78, glow: true),
                      const SizedBox(height: 22),
                      _VpnIllustration(
                        accent: presentation.accent,
                        icon: presentation.icon,
                      ),
                      const SizedBox(height: 26),
                      Text(
                        presentation.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        presentation.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _StatusPill(
                        label: presentation.statusLabel,
                        color: presentation.accent,
                        loading: state.isChecking,
                      ),
                      const SizedBox(height: 22),
                      WeekendGlass.strong(
                        radius: WeekendRadius.lg,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Why access is restricted',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              presentation.explanation,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Weekend checks Android\'s active network on this '
                              'device. It does not look up your IP address, send '
                              'network identifiers to Supabase, or record your '
                              'VPN provider.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.82),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      WeekendGlassButton(
                        label: state.isChecking
                            ? 'Checking connection…'
                            : 'Check connection again',
                        icon: state.isChecking ? null : Icons.refresh_rounded,
                        loading: state.isChecking,
                        onPressed: state.isChecking
                            ? null
                            : () => ref
                                  .read(vpnSecurityProvider.notifier)
                                  .check(),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: state.isChecking
                            ? null
                            : () => _showHelp(context),
                        child: const Text('How detection works'),
                      ),
                      if (state.status == VpnSecurityStatus.detectionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Detection could not complete'
                            '${state.reason == null ? '' : ' (${state.reason})'}. '
                            'Protected content stays hidden until a check '
                            'succeeds.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (state.status == VpnSecurityStatus.unsupported)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'VPN detection is only enforced on Android.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showWeekendGlassDialog<void>(
      context: context,
      title: 'How VPN detection works',
      icon: Icons.privacy_tip_outlined,
      content: const Text(
        'Android reports whether the active network uses a VPN transport. '
        'Weekend reads that local signal at launch, when the app returns to the '
        'foreground, and whenever Android reports a network change.\n\n'
        'Some configurations cannot be detected: split tunnelling, per-app '
        'proxies, private DNS and some OEM or always-on VPN implementations may '
        'not expose the VPN transport. Weekend therefore makes no claim that '
        'every possible tunnel is detected.\n\n'
        'If Android cannot determine the state, Weekend fails closed for '
        'private profiles, likes and chats. A retry is always available and a '
        'temporary error does not sign you out. No VPN provider name or network '
        'identifier leaves your device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _VpnPresentation {
  final String title;
  final String message;
  final String statusLabel;
  final String explanation;
  final IconData icon;
  final Color accent;

  const _VpnPresentation({
    required this.title,
    required this.message,
    required this.statusLabel,
    required this.explanation,
    required this.icon,
    required this.accent,
  });

  factory _VpnPresentation.from(VpnSecurityStatus status) {
    return switch (status) {
      VpnSecurityStatus.vpnDetected => const _VpnPresentation(
        title: 'VPN detected',
        message:
            'Please disconnect your VPN to continue using Weekend. Once your '
            'VPN is disconnected, we\'ll check your connection again '
            'automatically.',
        statusLabel: 'VPN active · access paused',
        explanation:
            'Weekend hides private profiles, likes, matches and messages '
            'while a VPN is active. This keeps discovery and conversations '
            'consistent with your real, verified location and is part of '
            'Weekend\'s safety policy.',
        icon: Icons.vpn_key_off_rounded,
        accent: AppTheme.sunsetCoral,
      ),
      VpnSecurityStatus.noNetwork => const _VpnPresentation(
        title: 'No connection',
        message:
            'Weekend needs a network connection to verify your device. '
            'Connect to Wi-Fi or mobile data, then check again.',
        statusLabel: 'Network unavailable',
        explanation:
            'Android reports no active network. Protected content stays '
            'hidden rather than assuming the connection is safe.',
        icon: Icons.wifi_off_rounded,
        accent: AppTheme.warningAmber,
      ),
      VpnSecurityStatus.detectionError => const _VpnPresentation(
        title: 'Connection check unavailable',
        message:
            'Weekend could not verify whether this connection is safe. Check '
            'again to restore access.',
        statusLabel: 'Verification required',
        explanation:
            'A temporary platform error is not treated as a disconnected VPN. '
            'Protected content stays hidden until Android can confirm the '
            'state, and you will not be signed out for a transient failure.',
        icon: Icons.gpp_maybe_rounded,
        accent: AppTheme.warningAmber,
      ),
      VpnSecurityStatus.unsupported => const _VpnPresentation(
        title: 'VPN protection unavailable',
        message:
            'This platform does not expose Android VPN detection. Weekend\'s '
            'VPN restriction applies to Android builds.',
        statusLabel: 'Not enforced on this platform',
        explanation:
            'No protected content is hidden because this build has no Android '
            'network stack to inspect.',
        icon: Icons.devices_other_rounded,
        accent: AppTheme.violet,
      ),
      VpnSecurityStatus.checking => const _VpnPresentation(
        title: 'Checking your connection',
        message:
            'Please wait while Weekend verifies that this network is safe.',
        statusLabel: 'Checking…',
        explanation:
            'Weekend checks the active Android network locally. No data is '
            'sent to a server for this check.',
        icon: Icons.shield_rounded,
        accent: AppTheme.violet,
      ),
      VpnSecurityStatus.unknown ||
      VpnSecurityStatus.clear => const _VpnPresentation(
        title: 'Connection secure',
        message: 'Returning to Weekend…',
        statusLabel: 'Verified',
        explanation:
            'The connection is verified. Protected content is '
            'available again.',
        icon: Icons.verified_user_rounded,
        accent: AppTheme.successGreen,
      ),
    };
  }
}

class _VpnIllustration extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _VpnIllustration({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      image: true,
      label: 'Network security illustration',
      child: SizedBox(
        width: 144,
        height: 144,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: isDark ? 0.20 : 0.14),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.65),
                border: Border.all(color: accent.withValues(alpha: 0.26)),
              ),
            ),
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.92),
                    (isDark ? AppTheme.violet : AppTheme.violetDeep).withValues(
                      alpha: 0.92,
                    ),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
            Positioned(
              right: 8,
              bottom: 18,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1A1228) : Colors.white,
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.lock_rounded, size: 18, color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: WeekendGlass.subtle(
        radius: WeekendRadius.pill,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: color,
                ),
              )
            else
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
