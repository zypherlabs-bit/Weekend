"""Navigation-flow checks.

The specification requires two journeys to exist and, critically, requires
that a successful authentication does NOT bounce the user back to sign-in.
These are STATIC route/redirect inspections, not device walkthroughs.
"""

from __future__ import annotations

import re

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    read_text,
)

ROUTER = REPO_ROOT / "lib" / "routing" / "app_router.dart"


def _router() -> str:
    return read_text(ROUTER)


def _routes() -> set[str]:
    return set(re.findall(r"path:\s*'([^']+)'", _router()))


def test_core_routes_registered() -> CheckResult:
    """STATIC: every screen the navigation map promises is routed."""
    routes = _routes()
    required = {
        "/",
        "/onboarding",
        "/auth",
        "/signup",
        "/home",
        "/edit-profile",
        "/explore",
        "/search",
        "/safety-center",
    }
    missing = sorted(r for r in required if r not in routes)
    return CheckResult(
        name="Core routes registered",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{len(routes)} routes" if not missing else f"missing: {missing}",
    )


def test_signup_journey_exists() -> CheckResult:
    """STATIC: Welcome -> Sign Up -> Passkey -> Details -> ... -> Discover.

    Each step in the onboarding chain must have a real destination.
    """
    router = _router()
    routes = _routes()
    chain_ok = all(
        p in routes
        for p in ("/onboarding", "/signup", "/edit-profile", "/location-permission", "/home")
    )
    # The wizard must be able to reach profile setup and then discovery.
    forwards = "needsProfileSetup" in router
    ok = chain_ok and forwards
    return CheckResult(
        name="Signup journey",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="chain complete" if ok else "onboarding chain incomplete",
    )


def test_signin_journey_exists() -> CheckResult:
    """STATIC: Sign In -> Passkey -> Discover is wired."""
    auth = read_text(REPO_ROOT / "lib" / "features" / "auth" / "auth_screen.dart")
    router = _router()
    offers_passkey = "Sign in with Passkey" in auth
    goes_home = "/home" in router
    ok = offers_passkey and goes_home
    return CheckResult(
        name="Signin journey",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="passkey -> home" if ok else "passkey sign-in not wired",
    )


def test_no_auth_loop_after_login() -> CheckResult:
    """STATIC: the redirect does not send an authenticated user to /auth.

    The historical bug this guards against: after a successful passkey sign-in
    the router rebuilt itself and threw the user back through the entry screens.
    The guard is a single router instance plus an explicit authenticated-user
    redirect away from the auth routes.
    """
    router = _router()
    # The historical bug: the router provider watched authState, so every auth
    # emission rebuilt GoRouter at initialLocation '/', throwing the user back
    # through the entry screens after a successful sign-in. The fix is a single
    # router instance driven by refreshListenable and a `ref.read` inside the
    # redirect. Comments are stripped first: the file documents the old bug in
    # prose that names `ref.watch(authStateProvider)`, which would otherwise be
    # misread as live code.
    code = re.sub(r"//.*?$", "", router, flags=re.M)
    single_instance = (
        "refreshListenable" in code
        and "ref.watch(authStateProvider)" not in code
        and "ref.read(authStateProvider)" in code
    )
    unauth_guard = code.find("if (!isAuthenticated)")
    entry_guard = re.search(
        r"isEntryScreen\s*&&\s*!authState\.needsProfileSetup\)\s*return\s+'/home'",
        code,
    )
    ok = (
        single_instance
        and unauth_guard > 0
        and entry_guard is not None
        and entry_guard.start() > unauth_guard
        and bool(
            re.search(
                r"if \(!isAuthenticated\)[\s\S]{0,200}?return\s+'/onboarding'", code
            )
        )
    )
    return CheckResult(
        name="No auth loop after login",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "single router instance, forwards to /home"
            if ok
            else "authenticated user may be redirected to auth"
        ),
    )


def test_search_screen_is_reachable() -> CheckResult:
    """STATIC: the advanced search screen is routed AND linked from the UI."""
    routed = "/search" in _routes()
    home = read_text(REPO_ROOT / "lib" / "features" / "home" / "home_screen.dart")
    linked = "'/search'" in home
    return CheckResult(
        name="Search screen reachable",
        status=Status.PASS if routed and linked else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="routed and linked" if routed and linked else "not reachable",
    )


def test_onboarding_screens_exist() -> CheckResult:
    """STATIC: the onboarding feature files are present on disk."""
    features = REPO_ROOT / "lib" / "features"
    required = [
        "onboarding/onboarding_screen.dart",
        "auth/auth_screen.dart",
        "auth/signup_wizard_screen.dart",
        "discovery/location_permission_screen.dart",
    ]
    missing = [r for r in required if not (features / r).exists()]
    return CheckResult(
        name="Onboarding screens exist",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all present" if not missing else f"missing: {', '.join(missing)}",
    )
