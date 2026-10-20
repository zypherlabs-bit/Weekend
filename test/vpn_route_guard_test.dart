import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/routing/vpn_route_guard.dart';

/// Route policy for the VPN guard.
///
/// These are pure functions, so the whole fail-closed contract can be pinned
/// without a GoRouter, a platform channel or a provider container.
void main() {
  group('public routes stay reachable', () {
    for (final route in const [
      '/',
      '/onboarding',
      '/auth',
      '/signup',
      '/confirm-email',
      '/mfa-challenge',
      '/vpn-blocked',
    ]) {
      test('$route is not protected', () {
        expect(isProtectedWeekendLocation(route), isFalse);
      });
    }
  });

  group('protected routes are protected by default', () {
    for (final route in const [
      '/home',
      '/discover',
      '/explore',
      '/profile',
      '/chat',
      '/plans',
      '/likes',
      '/notifications',
      '/settings',
      '/safety-center',
      '/edit-profile',
      '/future-screen-added-later',
    ]) {
      test('$route is protected', () {
        expect(isProtectedWeekendLocation(route), isTrue);
      });
    }
  });

  test('query strings and fragments do not change the verdict', () {
    expect(isProtectedWeekendLocation('/home?tab=2'), isTrue);
    expect(isProtectedWeekendLocation('/auth#reset'), isFalse);
  });

  test('a malformed location fails closed', () {
    expect(isProtectedWeekendLocation('http://[::1'), isTrue);
  });

  group('redirect while protected content is blocked', () {
    test('protected route redirects to the blocker', () {
      expect(
        vpnRedirectTarget(
          location: '/home',
          blocksProtectedContent: true,
          accessConfirmed: false,
          isAuthenticated: true,
          restoreLocation: null,
        ),
        '/vpn-blocked',
      );
    });

    test('the blocker itself is not re-redirected', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: true,
          accessConfirmed: false,
          isAuthenticated: true,
          restoreLocation: null,
        ),
        isNull,
      );
    });

    test('public routes stay reachable while blocked', () {
      expect(
        vpnRedirectTarget(
          location: '/auth',
          blocksProtectedContent: true,
          accessConfirmed: false,
          isAuthenticated: false,
          restoreLocation: null,
        ),
        isNull,
      );
    });

    test('the blocked destination is reported for later restore', () {
      String? remembered;
      vpnRedirectTarget(
        location: '/chat/42',
        blocksProtectedContent: true,
        accessConfirmed: false,
        isAuthenticated: true,
        restoreLocation: null,
        onBlocked: (location) => remembered = location,
      );
      expect(remembered, '/chat/42');
    });
  });

  group('leaving the blocker', () {
    test('unknown state keeps the user on the blocker', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: false,
          accessConfirmed: false,
          isAuthenticated: true,
          restoreLocation: '/home',
        ),
        isNull,
      );
    });

    test('a confirmed clear result restores the prior destination', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: false,
          accessConfirmed: true,
          isAuthenticated: true,
          restoreLocation: '/chat/42',
        ),
        '/chat/42',
      );
    });

    test('a confirmed clear result without a memory goes home', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: false,
          accessConfirmed: true,
          isAuthenticated: true,
          restoreLocation: null,
        ),
        '/home',
      );
    });

    test('a signed-out user returns to onboarding, never to /home', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: false,
          accessConfirmed: true,
          isAuthenticated: false,
          restoreLocation: null,
        ),
        '/onboarding',
      );
    });

    test('a stale protected memory is ignored', () {
      expect(
        vpnRedirectTarget(
          location: '/vpn-blocked',
          blocksProtectedContent: false,
          accessConfirmed: true,
          isAuthenticated: true,
          restoreLocation: '/home?x=1',
        ),
        '/home?x=1',
      );
    });
  });

  test('an allowed location is never redirected', () {
    expect(
      vpnRedirectTarget(
        location: '/home',
        blocksProtectedContent: false,
        accessConfirmed: true,
        isAuthenticated: true,
        restoreLocation: null,
      ),
      isNull,
    );
  });
}
