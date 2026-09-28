"""Supabase configuration and live database verification.

Live checks are read-only and never modify production data. When credentials or
a Management API token are unavailable the result is NOT VERIFIED, never PASS.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    have_live_config,
    management_token,
    migration_text,
    migrations,
    read_text,
    supabase_env,
)


def test_migrations_present() -> CheckResult:
    """STATIC: the schema is delivered as ordered, numbered migrations."""
    files = migrations()
    ok = len(files) >= 5 and all(f.name[0].isdigit() for f in files)
    return CheckResult(
        name="Migrations present",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{len(files)} migrations",
    )


def test_migration_numbering_sequential() -> CheckResult:
    """STATIC: migration numbers are unique and contiguous."""
    numbers = []
    for path in migrations():
        stem = path.stem.split("_")[0]
        if stem.isdigit():
            numbers.append(int(stem))
    gaps = [n for i, n in enumerate(numbers[1:], 1) if n != numbers[i - 1] + 1]
    ok = bool(numbers) and not gaps
    return CheckResult(
        name="Migration numbering",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{min(numbers)}..{max(numbers)}" if numbers else "none",
    )


def test_core_tables_defined() -> CheckResult:
    """STATIC: every table the app depends on is created in a migration."""
    sql = migration_text().lower()
    required = [
        "profiles",
        "profile_photos",
        "likes",
        "passes",
        "matches",
        "messages",
        "blocks",
        "reports",
        "user_settings",
        "plans",
    ]
    missing = [t for t in required if f"create table public.{t}" not in sql]
    return CheckResult(
        name="Core tables defined",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all present" if not missing else f"missing: {', '.join(missing)}",
    )


def test_indexes_present() -> CheckResult:
    """STATIC: the hot query paths are indexed."""
    sql = migration_text().lower()
    required = [
        "idx_profiles_city",
        "idx_profiles_gender",
        "idx_profiles_location",
        "idx_messages_conversation",
        "idx_matches_user_a",
    ]
    missing = [i for i in required if i not in sql]
    return CheckResult(
        name="Indexes present",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="present" if not missing else f"missing: {', '.join(missing)}",
    )


def test_rpc_functions_defined() -> CheckResult:
    """STATIC: the discovery and matching RPCs exist."""
    sql = migration_text().lower()
    required = [
        "get_nearby_profiles",
        "get_matches_for_user",
        "search_profiles",
        "check_mutual_like",
    ]
    missing = [f for f in required if f"function public.{f}(" not in sql]
    return CheckResult(
        name="RPC functions defined",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all present" if not missing else f"missing: {', '.join(missing)}",
    )


def test_realtime_publication() -> CheckResult:
    """STATIC: messaging tables are added to the Realtime publication."""
    sql = migration_text().lower()
    ok = "supabase_realtime" in sql and "publication" in sql
    return CheckResult(
        name="Realtime publication",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="configured" if ok else "not configured",
    )


def test_edge_functions_present() -> CheckResult:
    """STATIC: the Edge Functions the client invokes actually exist."""
    functions_dir = REPO_ROOT / "supabase" / "functions"
    present = (
        sorted(p.name for p in functions_dir.iterdir() if p.is_dir())
        if functions_dir.exists()
        else []
    )
    required = ["get-photo-urls", "account-deletion"]
    missing = [f for f in required if f not in present]
    return CheckResult(
        name="Edge Functions present",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=", ".join(present) if present else "none",
    )

# ---------------------------------------------------------------------------
# RUNTIME: live project (read-only)
# ---------------------------------------------------------------------------

def _rest_get(path: str) -> tuple[int, str]:
    env = supabase_env()
    req = urllib.request.Request(
        f"{env['SUPABASE_URL'].rstrip('/')}/rest/v1/{path}",
        headers={
            "apikey": env["SUPABASE_ANON_KEY"],
            "Authorization": f"Bearer {env['SUPABASE_ANON_KEY']}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return 0, str(exc)


def _mgmt_query(sql: str) -> list[dict]:
    """Run a read-only SQL query through the Supabase Management API."""
    env = supabase_env()
    ref = env["SUPABASE_URL"].rstrip("/").split("//")[-1].split(".")[0]
    payload = json.dumps({"query": sql}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=payload,
        headers={
            "Authorization": f"Bearer {management_token()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def test_live_backend_reachable() -> CheckResult:
    """RUNTIME: the configured Supabase project answers REST requests."""
    if not have_live_config():
        return CheckResult(
            name="Live Supabase reachable",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no live credentials configured",
        )
    code, _ = _rest_get("interests?select=id&limit=1")
    return CheckResult(
        name="Live Supabase reachable",
        status=Status.PASS if code == 200 else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"HTTP {code}",
    )


def test_live_schema_has_search_profiles() -> CheckResult:
    """RUNTIME: the advanced-search function is installed on the project."""
    if not have_live_config() or not management_token():
        return CheckResult(
            name="Live search_profiles installed",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="needs a Management API token",
        )
    try:
        rows = _mgmt_query(
            "select count(*)::int as n from pg_proc p "
            "join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname = 'public' and p.proname = 'search_profiles'"
        )
        count = int(rows[0]["n"]) if rows else 0
        return CheckResult(
            name="Live search_profiles installed",
            status=Status.PASS if count else Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail=f"{count} overload(s) on the live project",
        )
    except Exception as exc:  # noqa: BLE001
        return CheckResult(
            name="Live search_profiles installed",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"query failed: {type(exc).__name__}",
        )


def test_live_age_not_fabricated() -> CheckResult:
    """RUNTIME: the DEPLOYED functions no longer contain `else 25`.

    Reads prosrc from the live catalog, so a stale deployment is caught even
    when the repository has already been fixed.
    """
    if not have_live_config() or not management_token():
        return CheckResult(
            name="Live age not fabricated",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="needs a Management API token",
        )
    try:
        rows = _mgmt_query(
            "select proname, (position('else 25' in prosrc) > 0) as fake "
            "from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname = 'public' and p.proname in "
            "('get_nearby_profiles','get_matches_for_user','search_profiles')"
        )
        bad = [r["proname"] for r in rows if r.get("fake")]
        return CheckResult(
            name="Live age not fabricated",
            status=Status.PASS if rows and not bad else Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail=(
                f"checked {len(rows)} live function(s), none fabricate age"
                if rows and not bad
                else f"fabricates age: {', '.join(bad)}"
            ),
        )
    except Exception as exc:  # noqa: BLE001
        return CheckResult(
            name="Live age not fabricated",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"query failed: {type(exc).__name__}",
        )


def test_client_calls_only_real_edge_functions() -> CheckResult:
    """STATIC: no Dart source invokes an Edge Function that does not exist.

    This is the exact failure that made the old passkey flow unrunnable: it
    posted to `passkey-register` / `passkey-authenticate`, which were never
    deployed, so the ceremony could only ever fail.
    """
    functions_dir = REPO_ROOT / "supabase" / "functions"
    present = (
        {p.name for p in functions_dir.iterdir() if p.is_dir()}
        if functions_dir.exists()
        else set()
    )
    pattern = re.compile(r"functions\.invoke\(\s*'([a-z0-9-]+)'", re.I)
    missing: set[str] = set()
    for path in (REPO_ROOT / "lib").rglob("*.dart"):
        for name in pattern.findall(read_text(path)):
            if name not in present:
                missing.add(name)
    return CheckResult(
        name="Client invokes real functions",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "all invocations resolve"
            if not missing
            else f"missing: {', '.join(sorted(missing))}"
        ),
    )
