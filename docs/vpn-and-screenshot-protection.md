# VPN-aware access control and screen-capture protection

This page documents two Android-side protections that were added to Weekend, what
they actually enforce, how they are tested, and where they stop. Both are
described from the code in this repository, not from intent.

---

## 1. VPN-aware access control

### What the policy is

While the device routes traffic through a VPN, Weekend hides protected content:
private profiles, discovery results, likes, matches, messages and plans. Public
screens - onboarding, sign-in, sign-up, password reset, e-mail confirmation, the
blocker itself - stay reachable.

The rule exists so that discovery and conversations stay consistent with the
user's real, verified location. It is a product safety rule, not a claim that a
VPN is malicious.

### How detection works

| Layer | File | Responsibility |
|---|---|---|
| Native detector | `android/app/src/main/kotlin/com/weekend/app/VpnSecurityChannel.kt` | Reads `ConnectivityManager` + `NetworkCapabilities.TRANSPORT_VPN`; exposes a `MethodChannel` (`check`) and an `EventChannel` for network changes |
| Channel client | `lib/services/vpn_security_service.dart` | Maps the native payload into `VpnDetectionResult`; returns `unsupported` on non-Android platforms |
| Reactive state | `lib/providers/vpn_security_provider.dart` | Single source of truth, one check at a time, remembers the blocked destination |
| Route policy | `lib/routing/vpn_route_guard.dart` | Pure allow/redirect decisions, unit-tested without GoRouter |
| Blocker UI | `lib/features/security/vpn_blocked_screen.dart` | Explains the current state and offers a retry |
| Lifecycle gate | `lib/features/security/vpn_security_gate.dart` | Checks on launch and on every resume |

Details that matter:

- The active network is inspected first, then `allNetworks`, so a per-app VPN
  that is not the default network is still detected.
- Only `{status, transportVpn, validated, reason}` crosses the channel. No IP
  address, provider name or network identifier is ever collected, logged or sent
  to Supabase.
- Detection consumes `ACCESS_NETWORK_STATE`, which the app already declared for
  the Supabase client. No new permission, no accessibility service, no
  device-admin, no usage access.
- Checks are event-driven: launch, resume, and Android's own network callbacks.
  There is no timer and no polling loop.

### States

| State | Meaning | Protected content |
|---|---|---|
| `vpn` | Android reports a VPN transport | blocked |
| `no_network` | No active network | blocked |
| `error` | The platform could not answer | blocked |
| `unknown` / `checking` | No definitive answer yet | blocked (no claim of a VPN) |
| `clear` | No VPN transport reported | allowed |
| `unsupported` | Non-Android platform | allowed (the policy is Android-only) |

`unknown` and `checking` deliberately do **not** claim a VPN was found; they keep
the guard engaged without telling the user something untrue. The UI never says
"VPN detected" for a platform error or for being offline.

### Behaviour while blocked

- The router redirects to `/vpn-blocked`; this is the only protected route that
  is reachable, and it cannot redirect to itself.
- Back navigation cannot restore protected content: the blocker is wrapped in
  `PopScope(canPop: false)`, and the decision lives in the router rather than in
  a screen, so deep links are covered too.
- A retry button performs a fresh check. No sign-out, no permanent lockout: a
  transient failure leaves the session intact.
- Once a check comes back clear, the destination the user was heading for is
  restored (`vpnSecurityProvider.restoreLocation`).

### Limits (stated in the UI as well)

Android can only report transports the platform exposes. Split tunnelling,
per-app proxies, private DNS and some OEM or always-on VPN implementations may
not surface a VPN transport. Weekend therefore makes no claim that every
possible tunnel is detected.

### Tests

- `test/vpn_route_guard_test.dart` - public/protected classification, malformed
  URIs failing closed, restore/redirect behaviour, no restore for signed-out
  users.
- `test/vpn_security_provider_test.dart` - the full `accessConfirmed` matrix,
  single-check-at-a-time behaviour, event-driven updates (proving no re-check on
  a network event), error handling, retry, unsupported platforms, disposal.
- `test/vpn_blocked_screen_test.dart` - each state renders its own explanation,
  a retry re-checks and can clear, "no bypass" is asserted, back cannot restore
  content, and the help sheet admits the detection gaps.

---

## 2. Screen-capture protection

### What is enforced

`MainActivity` applies
`WindowManager.LayoutParams.FLAG_SECURE` in `onCreate`, before the Flutter engine
attaches, and disables the recent-apps screenshot on Android 13+
(`setRecentsScreenshotEnabled(false)`).

Because the whole Flutter UI lives in that single activity, this covers every
screen and the thumbnail Android stores for the task switcher. The flag is
re-applied on each activity recreation, so rotation or process restore cannot
drop it.

### What is not done

- No root, emulator or hooking detection.
- No use of accessibility services or device-admin rights.
- No attempt to detect screen recording apps, and no claim to.

### Honest limitation

`FLAG_SECURE` is a supported Android defence, not a guarantee. A camera pointed
at the screen, a rooted or modified device, or an OEM that does not honour the
flag is outside the platform contract. Weekend states this rather than
overpromising.

### Tests

There is no automated assertion for a window flag from the Dart test suite; the
change is verified by code review of `MainActivity.kt` and by the release build
compiling with it. It is listed as such rather than claimed as tested behaviour.
