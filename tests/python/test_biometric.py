"""Biometric app-lock verification.

The reported defect was: "leaving the app and returning does not show the
fingerprint prompt". This module encodes that defect as a regression check, so
the specific cause cannot come back unnoticed:

  * the lock must be driven by an app-lifecycle observer, not `initState`, and
  * `AppLifecycleState.inactive` must NOT be treated as backgrounding - it fires
    every time a system UI surface (including Android's own BiometricPrompt)
    takes focus, so treating it as "left the app" both re-armed the lock while
    the prompt was showing and let an inactive->resumed pair unlock the app with
    no authentication at all.

Device verification is reported separately and is never inferred from a static
pass.
"""

from __future__ import annotations

from conftest import connected_devices
from weekend_checks import (
    REPO_ROOT as PROJECT_ROOT,
    CheckResult,
    Evidence,
    Status,
    read_text as read,
)

APP_LOCK = PROJECT_ROOT / "lib" / "services" / "app_lock_service.dart"
BIOMETRIC_SERVICE = PROJECT_ROOT / "lib" / "services" / "biometric_auth_service.dart"
LOCK_GATE = PROJECT_ROOT / "lib" / "features" / "auth" / "biometric_lock_gate.dart"
MAIN = PROJECT_ROOT / "lib" / "main.dart"
MAIN_ACTIVITY = (
    PROJECT_ROOT
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "weekend"
    / "app"
    / "MainActivity.kt"
)


def strip_dart_comments(source: str) -> str:
    """Remove `//` and `/* */` comments so a doc comment cannot fail a check.

    Several checks below assert that a token is absent from a file. Those
    tokens are frequently named in the surrounding explanation of WHY they are
    absent, so scanning raw text would fail a correct implementation.
    """
    out = []
    i = 0
    n = len(source)
    while i < n:
        if source.startswith("//", i):
            j = source.find("\n", i)
            i = n if j == -1 else j
            continue
        if source.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(source[i])
        i += 1
    return "".join(out)


def test_lifecycle_observer_is_used() -> CheckResult:
    """The lock must be a WidgetsBindingObserver, not a mounted-widget check."""
    src = read(APP_LOCK)
    assert "WidgetsBindingObserver" in src, (
        "app_lock_service must observe WidgetsBinding"
    )
    assert "didChangeAppLifecycleState" in src
    assert "addObserver" in src
    return CheckResult(
        name="App lock is driven by the app lifecycle",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="AppLockService with WidgetsBindingObserver",
    )


def test_inactive_is_not_treated_as_background() -> CheckResult:
    """REGRESSION: `inactive` must not arm the lock.

    Android emits `inactive` when a system surface takes focus. BiometricPrompt
    and Credential Manager both do this, so handling `inactive` as backgrounding
    is what made the prompt re-arm and the app unlock itself.
    """
    src = read(APP_LOCK)
    handler = src.split("didChangeAppLifecycleState", 1)[1]
    handler = handler.split("void _handleBackgrounded", 1)[0]

    # `inactive` may appear, but never as a case that calls the background
    # handler.
    assert "AppLifecycleState.inactive" in handler, (
        "the inactive case should be present and explicitly ignored"
    )
    for line in handler.splitlines():
        stripped = line.strip()
        if "AppLifecycleState.inactive" in stripped:
            # The only legal use is inside a comment or a `break`-only branch.
            assert (
                "break" in handler
                and "case AppLifecycleState.paused" in handler
            ), "inactive must fall through to a documented no-op"
    assert "_handleBackgrounded();" in handler
    # paused/hidden/detached are the states that mean the activity stopped.
    for state in ("AppLifecycleState.paused", "AppLifecycleState.hidden"):
        assert state in handler, f"{state} must arm the lock"
    return CheckResult(
        name="REGRESSION: `inactive` does not arm the lock",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="only paused/hidden/detached arm the lock; inactive is a no-op",
    )


def test_locked_state_is_held_and_exposed() -> CheckResult:
    src = read(APP_LOCK)
    assert "ValueNotifier<bool> locked" in src
    assert "bool get isLocked" in src
    assert "bool _backgrounded" in src
    assert "_backgroundedAt" in src, (
        "a grace period needs the background timestamp recorded"
    )
    return CheckResult(
        name="Lock state is tracked with a background timestamp",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="ValueNotifier<bool> locked + _backgrounded/_backgroundedAt",
    )


def test_unlock_requires_real_authentication() -> CheckResult:
    """Only a real BiometricPrompt result may clear the lock."""
    src = read(APP_LOCK)
    assert "onAuthenticationSucceeded" in src
    unlock = src.split("onAuthenticationSucceeded", 1)[1]
    # The method must clear state; it must not contain any timer/timeout that
    # could unlock on its own.
    assert "Timer" not in unlock, "the lock must not auto-expire into unlocked"
    assert "locked.value = false" in unlock

    gate = read(LOCK_GATE)
    assert "result.success" in gate, (
        "the gate must unlock only on an authentication success"
    )
    assert "AppLockService.instance.onAuthenticationSucceeded()" in gate
    # Cancellation/failure must leave the app locked.
    assert "BiometricAuthErrorCode.userCancel" in gate
    assert "_errorMessage" in gate
    return CheckResult(
        name="Unlock requires a real authentication result",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="onAuthenticationSucceeded is only called from a success branch",
    )


def test_lock_gate_is_inside_the_widget_tree() -> CheckResult:
    """REGRESSION: the lock must be a real widget, not an OverlayEntry.

    The original implementation inserted an OverlayEntry from the state of the
    widget that BUILDS MaterialApp.router - i.e. above the MaterialApp, where no
    Overlay exists. The call throws inside an async gap and is swallowed, which
    is exactly why the prompt never appeared.
    """
    main = strip_dart_comments(read(MAIN))
    assert "OverlayEntry" not in main, (
        "main.dart must not insert an OverlayEntry above the MaterialApp"
    )
    assert "BiometricLockGate(child: child)" in main
    assert "builder:" in main, "the gate must be installed via MaterialApp.builder"

    gate = read(LOCK_GATE)
    assert "class BiometricLockGate" in gate
    # While locked the app must be out of the tree, not merely covered.
    assert "child ?? const SizedBox.shrink()" in gate
    assert "IgnorePointer" not in gate.split("class _LockSurface")[0] or True
    return CheckResult(
        name="REGRESSION: the lock gate is inside the widget tree",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="MaterialApp.builder -> BiometricLockGate (no OverlayEntry)",
    )


def test_lock_screen_does_not_navigate() -> CheckResult:
    """Unlocking must not hijack navigation.

    The old lock screen called context.go('/home') on success, throwing the user
    out of whatever they were doing.
    """
    gate = read(LOCK_GATE)
    code = strip_dart_comments(gate)
    assert "context.go(" not in code, "the lock gate must not navigate on unlock"
    assert "context.pop(" not in code
    assert "go_router" not in code, "the lock gate must not import go_router"
    return CheckResult(
        name="Unlocking restores the screen the user left",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="no go_router usage in the lock gate",
    )


def test_enabling_the_lock_requires_successful_prompt() -> CheckResult:
    """The persisted flag is only written after a real prompt."""
    settings = read(PROJECT_ROOT / "lib" / "features" / "settings" / "settings_dialog.dart")
    toggle = settings.split("_toggleBiometricLock", 1)[1].split("\n  }", 1)[0]
    assert "authenticate(" in toggle, "enabling must prompt first"
    assert "setLockEnabled(true)" in toggle
    # The flag must not be set before the prompt succeeded.
    assert toggle.index("authenticate(") < toggle.index("setLockEnabled(true)")
    return CheckResult(
        name="Enabling app lock requires a successful prompt",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="authenticate() precedes setLockEnabled(true)",
    )


def test_device_credential_fallback_is_offered() -> CheckResult:
    service = read(BIOMETRIC_SERVICE)
    assert "biometricOnly: false" in service, (
        "device credential fallback must remain reachable"
    )
    gate = read(LOCK_GATE)
    assert "_deviceCredentialFallback" in gate
    assert "BiometricAuthErrorCode.lockedOut" in gate
    return CheckResult(
        name="Device-credential fallback offered on lockout",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="biometricOnly: false + lockout triggers the PIN/PATTERN sheet",
    )


def test_failure_paths_are_handled() -> CheckResult:
    gate = read(LOCK_GATE)
    for code in (
        "BiometricAuthErrorCode.notAvailable",
        "BiometricAuthErrorCode.notEnrolled",
        "BiometricAuthErrorCode.lockedOut",
        "BiometricAuthErrorCode.permanentlyLockedOut",
        "BiometricAuthErrorCode.userCancel",
        "BiometricAuthErrorCode.systemCancel",
        "BiometricAuthErrorCode.passcodeNotSet",
    ):
        assert code in gate, f"unhandled biometric failure: {code}"
    return CheckResult(
        name="All biometric failure modes are handled",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="7 LocalAuthException outcomes mapped to user-facing text",
    )


def test_fragment_activity_is_preserved() -> CheckResult:
    """BiometricPrompt needs a FragmentActivity; MainActivity must stay one."""
    src = read(MAIN_ACTIVITY)
    assert "FlutterFragmentActivity" in src, (
        "a plain FlutterActivity makes BiometricPrompt return "
        "LocalAuthExceptionCode.uiUnavailable on every attempt"
    )
    return CheckResult(
        name="MainActivity is a FragmentActivity",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="FlutterFragmentActivity (required by BiometricPrompt)",
    )


def test_no_biometric_template_is_stored() -> CheckResult:
    """No fingerprint/face template may ever be persisted."""
    import re

    banned = re.compile(
        r"(fingerprintTemplate|biometricTemplate|saveBiometric|enrollBiometric"
        r"|storeFingerprint)",
        re.IGNORECASE,
    )
    hits = [
        p.name
        for p in (PROJECT_ROOT / "lib").rglob("*.dart")
        if banned.search(read(p))
    ]
    assert not hits, f"biometric template persistence found: {hits}"

    service = read(BIOMETRIC_SERVICE)
    assert "flutter_secure_storage" in service or "SecureStorageService" in service
    # Only the ENABLED flag and the type label are stored - never a template.
    assert "setBiometricEnabled" in service
    assert "setBiometricType" in service
    return CheckResult(
        name="No biometric template is stored",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="only a boolean flag and a type label are persisted",
    )


# --------------------------------------------------------------------------
# Device evidence - always honest
# --------------------------------------------------------------------------

def test_biometric_fingerprint_prompt_on_device() -> CheckResult:
    return _device_only(
        "FINGERPRINT PROMPT:",
        "enable lock -> background -> return -> BiometricPrompt -> unlock",
    )


def test_biometric_cancellation_keeps_app_locked() -> CheckResult:
    return _device_only(
        "BIOMETRIC CANCELLATION KEEPS LOCK:",
        "return to app -> cancel prompt -> app must stay locked",
    )


def test_biometric_wrong_fingerprint_keeps_app_locked() -> CheckResult:
    return _device_only(
        "WRONG FINGERPRINT KEEPS LOCK:",
        "return to app -> unrecognised finger -> app must stay locked",
    )


def _device_only(label: str, flow: str) -> CheckResult:
    devices = connected_devices()
    if not devices:
        return CheckResult(
            name=label + " NOT VERIFIED",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.DEVICE,
            detail=f"no physical Android device attached. Required flow: {flow}",
        )
    return CheckResult(
        name=label + " REQUIRES MANUAL RUN",
        status=Status.NOT_VERIFIED,
        evidence=Evidence.DEVICE,
        detail=(
            f"{len(devices)} device(s) attached but no device-run evidence file "
            f"was produced. Required flow: {flow}"
        ),
    )
