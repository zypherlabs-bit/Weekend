import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/providers/vpn_security_provider.dart';
import 'package:weekend/services/vpn_security_service.dart';

/// Scriptable stand-in for the Android detector, so the provider contract can
/// be tested without a platform channel.
class FakeVpnDetectionService implements VpnDetectionService {
  FakeVpnDetectionService({
    this.isSupported = true,
    VpnDetectionResult? result,
  }) : result =
           result ??
           VpnDetectionResult(
             status: VpnSecurityStatus.clear,
             checkedAt: DateTime(2026, 1, 1),
           );

  @override
  final bool isSupported;

  VpnDetectionResult result;
  int checkCount = 0;
  bool disposed = false;

  final _controller = StreamController<VpnDetectionResult>.broadcast();

  void emit(VpnDetectionResult next) => _controller.add(next);

  @override
  Future<VpnDetectionResult> check() async {
    checkCount++;
    return result;
  }

  @override
  Stream<VpnDetectionResult> get changes => _controller.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}

ProviderContainer containerFor(FakeVpnDetectionService service) {
  final container = ProviderContainer(
    overrides: [vpnDetectionServiceProvider.overrideWithValue(service)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('fail-closed access policy', () {
    test('only a clear result confirms access', () {
      for (final status in VpnSecurityStatus.values) {
        final state = VpnSecurityState(status: status, supported: true);
        expect(
          state.accessConfirmed,
          status == VpnSecurityStatus.clear ||
              status == VpnSecurityStatus.unsupported,
          reason: 'unexpected accessConfirmed for $status',
        );
      }
    });

    test('vpn, error and no-network all block protected content', () {
      for (final status in const [
        VpnSecurityStatus.vpnDetected,
        VpnSecurityStatus.detectionError,
        VpnSecurityStatus.noNetwork,
      ]) {
        final state = VpnSecurityState(status: status, supported: true);
        expect(state.blocksProtectedContent, isTrue, reason: '$status');
      }
    });

    test('unknown and checking block without claiming a VPN', () {
      for (final status in const [
        VpnSecurityStatus.unknown,
        VpnSecurityStatus.checking,
      ]) {
        final state = VpnSecurityState(status: status, supported: true);
        expect(state.blocksProtectedContent, isFalse, reason: '$status');
        expect(state.accessConfirmed, isFalse, reason: '$status');
      }
    });

    test('unsupported platforms are not blocked', () {
      const state = VpnSecurityState(
        status: VpnSecurityStatus.unsupported,
        supported: false,
      );
      expect(state.blocksProtectedContent, isFalse);
      expect(state.accessConfirmed, isTrue);
    });
  });

  group('controller', () {
    test('starts unknown on a supported platform', () {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      final state = container.read(vpnSecurityProvider);

      expect(state.status, VpnSecurityStatus.unknown);
      expect(state.supported, isTrue);
      expect(state.accessConfirmed, isFalse);
    });

    test('initialize performs exactly one check and applies the result', () async {
      final service = FakeVpnDetectionService(
        result: VpnDetectionResult(
          status: VpnSecurityStatus.clear,
          checkedAt: DateTime(2026, 1, 2),
        ),
      );
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      expect(service.checkCount, 1);
      final state = container.read(vpnSecurityProvider);
      expect(state.status, VpnSecurityStatus.clear);
      expect(state.accessConfirmed, isTrue);
      expect(state.isChecking, isFalse);
    });

    test('initializing twice does not re-check', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      final notifier = container.read(vpnSecurityProvider.notifier);

      await notifier.initialize();
      await notifier.initialize();

      expect(service.checkCount, 1);
    });

    test('a VPN result blocks and records the reason', () async {
      final service = FakeVpnDetectionService(
        result: VpnDetectionResult(
          status: VpnSecurityStatus.vpnDetected,
          reason: 'transport_vpn',
          checkedAt: DateTime(2026, 1, 3),
        ),
      );
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      final state = container.read(vpnSecurityProvider);
      expect(state.isVpnDetected, isTrue);
      expect(state.blocksProtectedContent, isTrue);
      expect(state.accessConfirmed, isFalse);
      expect(state.reason, 'transport_vpn');
      expect(state.checkedAt, DateTime(2026, 1, 3));
    });

    test('a detection failure blocks rather than granting access', () async {
      final service = FakeVpnDetectionService(
        result: VpnDetectionResult.failure('vpn_check_failed'),
      );
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      final state = container.read(vpnSecurityProvider);
      expect(state.status, VpnSecurityStatus.detectionError);
      expect(state.blocksProtectedContent, isTrue);
      expect(state.accessConfirmed, isFalse);
      expect(state.reason, 'vpn_check_failed');
    });

    test('a connectivity event updates the state without polling', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();
      expect(service.checkCount, 1);

      service.emit(
        VpnDetectionResult(
          status: VpnSecurityStatus.vpnDetected,
          reason: 'network_callback',
          checkedAt: DateTime(2026, 1, 4),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(vpnSecurityProvider).isVpnDetected, isTrue);
      expect(service.checkCount, 1, reason: 'events must not trigger a re-check');
    });

    test('an event stream failure is treated as a blocking error', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      service._controller.addError(StateError('channel closed'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(vpnSecurityProvider);
      expect(state.status, VpnSecurityStatus.detectionError);
      expect(state.reason, 'vpn_event_stream_failed');
      expect(state.blocksProtectedContent, isTrue);
    });

    test('retry after a failure can clear access again', () async {
      final service = FakeVpnDetectionService(
        result: VpnDetectionResult.failure('vpn_check_failed'),
      );
      final container = containerFor(service);
      final notifier = container.read(vpnSecurityProvider.notifier);
      await notifier.initialize();
      expect(container.read(vpnSecurityProvider).accessConfirmed, isFalse);

      service.result = VpnDetectionResult(
        status: VpnSecurityStatus.clear,
        checkedAt: DateTime(2026, 1, 5),
      );
      await notifier.check();

      expect(container.read(vpnSecurityProvider).accessConfirmed, isTrue);
      expect(service.checkCount, 2);
    });

    test('an unsupported platform short-circuits without a channel call', () async {
      final service = FakeVpnDetectionService(isSupported: false);
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      final state = container.read(vpnSecurityProvider);
      expect(state.status, VpnSecurityStatus.unsupported);
      expect(state.accessConfirmed, isTrue);
      expect(service.checkCount, 0);
    });

    test('the protected location is remembered and can be cleared', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      final notifier = container.read(vpnSecurityProvider.notifier);
      await notifier.initialize();

      notifier.rememberProtectedLocation('/chat/42');
      expect(container.read(vpnSecurityProvider).restoreLocation, '/chat/42');

      // The blocker itself must never become the restore target.
      notifier.rememberProtectedLocation('/vpn-blocked');
      expect(container.read(vpnSecurityProvider).restoreLocation, '/chat/42');

      notifier.clearRestoreLocation();
      expect(container.read(vpnSecurityProvider).restoreLocation, isNull);
    });

    test('the routing fingerprint ignores the remembered location', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      final notifier = container.read(vpnSecurityProvider.notifier);
      await notifier.initialize();

      final before = container.read(vpnSecurityProvider).routingFingerprint;
      notifier.rememberProtectedLocation('/home');
      expect(
        container.read(vpnSecurityProvider).routingFingerprint,
        before,
      );
    });

    test('dispose releases the service and the subscription', () async {
      final service = FakeVpnDetectionService();
      final container = containerFor(service);
      await container.read(vpnSecurityProvider.notifier).initialize();

      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(service.disposed, isTrue);
    });
  });
}
