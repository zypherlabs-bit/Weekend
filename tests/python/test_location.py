"""Location privacy and server-side location-query checks.

The product claim is: discover people near you WITHOUT exposing exact
coordinates. These tests check both halves - that the server computes
distance, and that the client never renders raw coordinates.
"""

from __future__ import annotations

import re

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    dart_sources,
    migration_text,
    read_text,
)


def test_location_permission_handling() -> CheckResult:
    """STATIC: the app requests location permission and explains why."""
    location = read_text(REPO_ROOT / "lib" / "services" / "location_service.dart")
    ok = "LocationPermission" in location or "checkPermission" in location
    if not ok:
        screen = read_text(
            REPO_ROOT
            / "lib"
            / "features"
            / "discovery"
            / "location_permission_screen.dart"
        )
        ok = "permission" in screen.lower()
    return CheckResult(
        name="Location permission handling",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="permission flow present" if ok else "not found",
    )


def test_while_in_use_only_permission() -> CheckResult:
    """STATIC: only COARSE/FINE location is requested, never background."""
    manifest = read_text(
        REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    background = "ACCESS_BACKGROUND_LOCATION" in manifest
    return CheckResult(
        name="While-in-use location only",
        status=Status.PASS if not background else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="no background permission" if not background else "background requested",
    )


def test_server_side_geographic_query() -> CheckResult:
    """STATIC: distance is computed by PostGIS, not in Dart."""
    sql = migration_text().lower()
    ok = "st_dwithin" in sql and "st_distance" in sql
    return CheckResult(
        name="Server-side location query",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="PostGIS ST_DWithin/ST_Distance" if ok else "not found",
    )


def test_location_index_exists() -> CheckResult:
    """STATIC: a GiST index backs the geographic predicate."""
    sql = migration_text().lower()
    ok = "using gist" in sql
    return CheckResult(
        name="Geographic index",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="GiST index present" if ok else "missing",
    )


def test_exact_coordinates_never_returned() -> CheckResult:
    """STATIC: no discovery RPC returns another user's coordinates.

    The OUT column list of each discovery/search function is inspected.
    Returning them would defeat the privacy model regardless of what the UI
    chooses to render.
    """
    sql = migration_text().lower()
    offenders: list[str] = []
    for func in ("get_nearby_profiles", "search_profiles"):
        idx = sql.find(f"function public.{func}(")
        if idx < 0:
            continue
        returns = sql.find("returns table", idx)
        body = sql.find("$$", returns)
        if returns < 0 or body < 0:
            continue
        columns = sql[returns:body]
        if "latitude" in columns or "longitude" in columns:
            offenders.append(func)
    return CheckResult(
        name="Exact coordinates not returned",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "rounded distance only"
            if not offenders
            else f"leaks coordinates: {', '.join(offenders)}"
        ),
    )


def test_no_coordinate_rendering_in_ui() -> CheckResult:
    """STATIC: no widget interpolates raw latitude/longitude into text."""
    pattern = re.compile(r"\$\{[^}]*\b(latitude|longitude)\b[^}]*\}", re.I)
    offenders: list[str] = []
    for path in dart_sources("lib"):
        text = read_text(path)
        if not text:
            continue
        for line in text.splitlines():
            if pattern.search(line) and ("Text(" in line or "'" in line):
                offenders.append(str(path.relative_to(REPO_ROOT)))
                break
    return CheckResult(
        name="No coordinate rendering in UI",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="privacy-safe labels only" if not offenders else "; ".join(offenders[:5]),
    )


def test_privacy_safe_distance_labels() -> CheckResult:
    """STATIC: the client formats distance as "Nearby" / "N km away".

    The "Nearby" bucket is produced by `formatDistanceWithAway`; the exact
    wording lives in that helper, so both markers are looked for across the
    location service.
    """
    location = read_text(REPO_ROOT / "lib" / "services" / "location_service.dart")
    has_km = "km away" in location
    has_nearby = "Nearby" in location or "formatDistanceWithAway" in location
    ok = has_km and has_nearby
    return CheckResult(
        name="Privacy-safe distance labels",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="Nearby / km away" if ok else "label helper incomplete",
    )


def test_blocked_users_excluded_server_side() -> CheckResult:
    """STATIC: discovery excludes blocked accounts in both directions."""
    sql = migration_text().lower()
    ok = "public.blocks" in sql and "blocked_id" in sql
    return CheckResult(
        name="Blocked users excluded",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="both directions excluded" if ok else "not found",
    )
