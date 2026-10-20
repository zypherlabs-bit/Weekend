import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/vpn_security_provider.dart';
import '../../widgets/weekend_design_system.dart';

/// Owns the VPN lifecycle: starts the native listener after the first frame,
/// re-checks on every resume, and covers the last frame while a resumed check
/// is in flight so a just-backgrounded private screen is not exposed.
class VpnSecurityGate extends ConsumerStatefulWidget {
  final Widget child;

  const VpnSecurityGate({super.key, required this.child});

  @override
  ConsumerState<VpnSecurityGate> createState() => _VpnSecurityGateState();
}

class _VpnSecurityGateState extends ConsumerState<VpnSecurityGate>
    with WidgetsBindingObserver {
  bool _coverWhileChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(vpnSecurityProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;

    // Paint a neutral cover before the async platform check returns.  This is
    // what prevents a VPN that connected while Weekend was backgrounded from
    // flashing the previously visible protected screen on resume.
    setState(() => _coverWhileChecking = true);
    final controller = ref.read(vpnSecurityProvider.notifier);
    controller.check().whenComplete(() {
      if (!mounted) return;
      setState(() => _coverWhileChecking = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final checking = ref.watch(
      vpnSecurityProvider.select((state) => state.isChecking),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_coverWhileChecking && checking)
          const Positioned.fill(child: _SecurityCheckingCover()),
      ],
    );
  }
}

class _SecurityCheckingCover extends StatelessWidget {
  const _SecurityCheckingCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: WeekendAtmosphere(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WeekendLogo(size: 72, glow: true),
                const SizedBox(height: 24),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Checking your connection…',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
