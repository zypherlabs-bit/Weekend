import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/features/security/vpn_blocked_screen.dart';
import 'package:weekend/providers/vpn_security_provider.dart';
import 'package:weekend/services/vpn_security_service.dart';
import 'package:weekend/theme/app_theme.dart';

import 'vpn_security_provider_test.dart' show FakeVpnDetectionService;

/// The blocker must explain the real state, always offer a retry, and never
/// offer a way past the policy.
void main() {
  Future<ProviderContainer> pumpBlocker(
    WidgetTester tester,
    FakeVpnDetectionService service, {
    ThemeData? theme,
  }) async {
    final container = ProviderContainer(
      overrides: [vpnDetectionServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          home: const VpnBlockedScreen(),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('a detected VPN explains itself and offers no bypass',
      (tester) async {
    final service = FakeVpnDetectionService(
      result: VpnDetectionResult(
        status: VpnSecurityStatus.vpnDetected,
        reason: 'transport_vpn',
        checkedAt: DateTime(2026, 1, 3),
      ),
    );
    final container = await pumpBlocker(tester, service);
    await container.read(vpnSecurityProvider.notifier).check();
    await tester.pumpAndSettle();

    expect(find.text('VPN detected'), findsOneWidget);
    expect(find.text('VPN active · access paused'), findsOneWidget);
    expect(find.text('Check connection again'), findsOneWidget);

    // No escape hatch: nothing on this screen may resume protected content.
    for (final forbidden in const [
      'Continue anyway',
      'Continue',
      'Skip',
      'Ignore',
      'Proceed',
    ]) {
      expect(find.text(forbidden), findsNothing, reason: forbidden);
    }
  });

  testWidgets('a transient detection error says access is hidden, retryable',
      (tester) async {
    final service = FakeVpnDetectionService(
      result: VpnDetectionResult.failure('native_channel_failed'),
    );
    final container = await pumpBlocker(tester, service);
    await container.read(vpnSecurityProvider.notifier).check();
    await tester.pumpAndSettle();

    expect(find.text('Connection check unavailable'), findsOneWidget);
    expect(
      find.textContaining('Protected content stays hidden until a check'),
      findsOneWidget,
    );
    expect(find.textContaining('native_channel_failed'), findsOneWidget);
    expect(find.text('Check connection again'), findsOneWidget);
  });

  testWidgets('offline is a distinct state, not reported as a VPN',
      (tester) async {
    final service = FakeVpnDetectionService(
      result: VpnDetectionResult(
        status: VpnSecurityStatus.noNetwork,
        checkedAt: DateTime(2026, 1, 4),
      ),
    );
    final container = await pumpBlocker(tester, service);
    await container.read(vpnSecurityProvider.notifier).check();
    await tester.pumpAndSettle();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Network unavailable'), findsOneWidget);
    expect(find.text('VPN detected'), findsNothing);
  });

  testWidgets('retry runs a fresh check and can confirm the connection',
      (tester) async {
    final service = FakeVpnDetectionService(
      result: VpnDetectionResult(
        status: VpnSecurityStatus.vpnDetected,
        checkedAt: DateTime(2026, 1, 5),
      ),
    );
    final container = await pumpBlocker(tester, service);
    await container.read(vpnSecurityProvider.notifier).check();
    await tester.pumpAndSettle();
    expect(find.text('VPN detected'), findsOneWidget);

    service.result = VpnDetectionResult(
      status: VpnSecurityStatus.clear,
      checkedAt: DateTime(2026, 1, 6),
    );
    await tester.ensureVisible(find.text('Check connection again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check connection again'));
    await tester.pumpAndSettle();

    expect(find.text('Connection secure'), findsOneWidget);
    expect(container.read(vpnSecurityProvider).accessConfirmed, isTrue);
  });

  testWidgets('the screen renders in light mode as well as dark', (tester) async {
    final service = FakeVpnDetectionService(
      result: VpnDetectionResult(
        status: VpnSecurityStatus.vpnDetected,
        checkedAt: DateTime(2026, 1, 7),
      ),
    );
    final container = await pumpBlocker(
      tester,
      service,
      theme: AppTheme.lightTheme,
    );
    await container.read(vpnSecurityProvider.notifier).check();
    await tester.pumpAndSettle();

    expect(find.text('VPN detected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back cannot restore protected content', (tester) async {
    final service = FakeVpnDetectionService();
    await pumpBlocker(tester, service);

    final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(popScope.canPop, isFalse);
  });

  testWidgets('the help sheet describes detection without overpromising',
      (tester) async {
    final service = FakeVpnDetectionService();
    await pumpBlocker(tester, service);

    await tester.ensureVisible(find.text('How detection works'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How detection works'));
    await tester.pumpAndSettle();

    expect(find.text('How VPN detection works'), findsOneWidget);
    expect(
      find.textContaining('split tunnelling'),
      findsOneWidget,
      reason: 'the sheet must admit detection gaps',
    );
    expect(
      find.textContaining('does not sign you out'),
      findsOneWidget,
    );
  });
}
