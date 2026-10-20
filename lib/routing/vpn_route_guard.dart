/// Pure route-policy helpers, kept out of `app_router.dart` so they can be
/// unit-tested without constructing a GoRouter or a provider container.
library;

/// Routes a visitor may see without a session or while the security guard is
/// engaged.  Everything else is protected by default: a new authenticated
/// screen added later is covered without remembering to update an allow-list.
const Set<String> _publicRoutes = {
  '/',
  '/onboarding',
  '/auth',
  '/signup',
  '/confirm-email',
  '/mfa-challenge',
  '/vpn-blocked',
};

/// True when [location] must not be shown while [blocksProtectedContent] is
/// true.  A malformed URI is treated as protected (fail closed).
bool isProtectedWeekendLocation(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null) return true;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return !_publicRoutes.contains(path);
}

/// Where GoRouter's redirect should send the current navigation, or null when
/// the location is allowed.
///
/// [onBlocked] is called with the destination that should be restored after a
/// successful re-check.  Passing a callback keeps this function pure.
String? vpnRedirectTarget({
  required String location,
  required bool blocksProtectedContent,
  required bool accessConfirmed,
  required bool isAuthenticated,
  required String? restoreLocation,
  void Function(String location)? onBlocked,
}) {
  final path = Uri.tryParse(location)?.path ?? location;

  if (blocksProtectedContent) {
    if (!isProtectedWeekendLocation(location)) return null;
    onBlocked?.call(location);
    return '/vpn-blocked';
  }

  // Only leave the blocker once access is genuinely confirmed. `unknown` and
  // `checking` are not clear, so the guard keeps the last safe destination.
  if (path == '/vpn-blocked') {
    if (!accessConfirmed) return null;
    if (!isAuthenticated) return '/onboarding';
    if (restoreLocation != null &&
        isProtectedWeekendLocation(restoreLocation)) {
      return restoreLocation;
    }
    return '/home';
  }

  return null;
}
