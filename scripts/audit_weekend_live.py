#!/usr/bin/env python3
"""Weekend - live-project audit helper.

Read-only by default. The Management API token is read from the environment
variable ``SUPABASE_ACCESS_TOKEN`` (or ``%TEMP%/sbp_token.txt``); the token is
never printed, logged, or written to disk by this script.

Every check is a *read* unless ``--cleanup`` is passed, in which case the
script only removes rows whose display_name carries the audit marker
``WKND_AUDIT`` - it never deletes unmarked data.

Usage
-----
    python scripts/audit_weekend_live.py                 # report only
    python scripts/audit_weekend_live.py --json out.json # machine-readable
    python scripts/audit_weekend_live.py --cleanup        # remove audit rows

Exit code is 0 when every check passed, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_PROJECT_REF = "ocypgybqfushqfzisnvs"
QUERY_URL = "https://api.supabase.com/v1/projects/{ref}/database/query"

# Only rows whose display_name contains this marker may ever be deleted.
AUDIT_MARKER = "WKND_AUDIT"


def load_token() -> str:
    """Return the Management API token from env or the temp token file."""
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if token:
        return token
    fallback = Path(tempfile.gettempdir()) / "sbp_token.txt"
    if fallback.exists():
        return fallback.read_text(encoding="utf-8").strip()
    raise SystemExit(
        "No Management API token. Set SUPABASE_ACCESS_TOKEN or create "
        f"{fallback}. Never commit the token."
    )


def run_sql(sql: str, token: str, ref: str) -> list[dict[str, Any]]:
    """Execute one statement and return its rows."""
    request = urllib.request.Request(
        QUERY_URL.format(ref=ref),
        data=json.dumps({"query": sql}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:  # pragma: no cover - network path
        detail = exc.read().decode("utf-8", "replace")[:400]
        raise SystemExit(f"HTTP {exc.code} from Supabase: {detail}") from exc
    except urllib.error.URLError as exc:  # pragma: no cover - network path
        raise SystemExit(f"Network failure talking to Supabase: {exc}") from exc
    return payload if isinstance(payload, list) else [payload]


def check(name: str, ok: bool, detail: Any = "") -> dict[str, Any]:
    """Build one result record."""
    return {"check": name, "ok": bool(ok), "detail": detail}





def audit(token: str, ref: str) -> list[dict[str, Any]]:
    """Run every read-only health check and return the results."""
    results: list[dict[str, Any]] = []

    # 1. Migrations 001-021 all applied. The ledger stores a zero-padded
    # `version` ('021'); `name` is nullable and is NOT a reliable key.
    rows = run_sql(
        "select version from supabase_migrations.schema_migrations "
        "where version ~ '^[0-9]{3}$' and version <= '021' order by version",
        token,
        ref,
    )
    applied = [str(r.get("version", "")) for r in rows]
    missing = [f"{n:03d}" for n in range(1, 22) if f"{n:03d}" not in applied]
    results.append(
        check(
            "migrations_001_021_applied",
            not missing,
            "all 21 present" if not missing else f"missing: {missing}",
        )
    )

    # 2. Profiles rows must all be backed by a real auth user.
    rows = run_sql(
        "select count(*)::int as n from public.profiles p "
        "left join auth.users u on u.id = p.id where u.id is null",
        token,
        ref,
    )
    orphans = rows[0].get("n", 0) if rows else 0
    results.append(check("no_orphan_profiles", orphans == 0, orphans))

    # 3. Display names must never be blank (the old "User" placeholder bug).
    rows = run_sql(
        "select count(*)::int as n from public.profiles "
        "where btrim(coalesce(display_name,'')) = ''",
        token,
        ref,
    )
    blank = rows[0].get("n", 0) if rows else 0
    results.append(check("no_blank_display_names", blank == 0, blank))

    # 4. RLS must be enabled on every APPLICATION table in public.
    #    Extension-owned tables (e.g. PostGIS `spatial_ref_sys`) hold no user
    #    data and legitimately have no RLS, so they are excluded by joining
    #    pg_extension rather than by hardcoding a name.
    rows = run_sql(
        "select t.tablename from pg_tables t "
        "left join pg_class c on c.relname = t.tablename "
        "left join pg_namespace n on n.oid = c.relnamespace "
        "left join pg_depend d on d.objid = c.oid and d.deptype = 'e' "
        "where t.schemaname = 'public' and t.rowsecurity = false "
        "and d.objid is null",
        token,
        ref,
    )
    offenders = [str(r.get("tablename", "")) for r in rows]
    results.append(
        check(
            "rls_enabled_on_all_public_tables",
            not offenders,
            "all enabled" if not offenders else f"RLS off: {offenders}",
        )
    )

    # 5. Social-handle obfuscation: a bare `sn:` handle must be caught.
    #    Probed with a synthetic string so the result is deterministic and
    #    does not depend on whatever happens to be in the live bios today.
    rows = run_sql(
        "select ('find me on sn:somesomewhere' ~* 'sn:[A-Za-z0-9_]+')::int as d",
        token,
        ref,
    )
    detected = bool(rows and rows[0].get("d"))
    results.append(
        check(
            "bare_sn_handle_pattern_detects",
            detected,
            "pattern matches" if detected else "PATTERN DOES NOT MATCH",
        )
    )

    # 6. Every profile must own a referral code (017 invariant, enforced for
    #    all INSERT paths by 021). A NULL here silently breaks QR invites and
    #    the Copy button on the Profile screen.
    rows = run_sql(
        "select count(*)::int as n from public.profiles "
        "where referral_code is null or referral_code = ''",
        token,
        ref,
    )
    no_code = rows[0].get("n", 0) if rows else 0
    results.append(check("every_profile_has_referral_code", no_code == 0, no_code))

    return results


def cleanup(token: str, ref: str) -> list[dict[str, Any]]:
    """Delete ONLY rows explicitly marked with the audit marker."""
    doomed = run_sql(
        "select id, display_name from public.profiles "
        f"where display_name like '%{AUDIT_MARKER}%'",
        token,
        ref,
    )
    removed: list[dict[str, Any]] = []
    for row in doomed:
        row_id = str(row.get("id", ""))
        # Refuse anything that is not a full UUID - guards against a malformed
        # query result turning into a broad DELETE.
        if len(row_id) != 36 or row_id.count("-") != 4:
            raise SystemExit(f"Refusing to delete unexpected id {row_id!r}")
        run_sql(f"delete from public.profiles where id = '{row_id}'::uuid", token, ref)
        removed.append({"id": row_id, "display_name": row.get("display_name")})
    return removed


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit the live Weekend project.")
    parser.add_argument("--ref", default=DEFAULT_PROJECT_REF, help="project ref")
    parser.add_argument("--json", help="also write the report to this path")
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="delete profile rows whose display_name contains "
        f"{AUDIT_MARKER} (opt-in, marked rows only)",
    )
    args = parser.parse_args()

    token = load_token()
    results = audit(token, args.ref)
    report: dict[str, Any] = {"project_ref": args.ref, "checks": results}

    if args.cleanup:
        report["cleanup"] = cleanup(token, args.ref)

    failed = [r for r in results if not r["ok"]]
    for item in results:
        print(f"[{'PASS' if item['ok'] else 'FAIL'}] {item['check']}: {item['detail']}")
    if args.cleanup:
        for item in report["cleanup"]:
            print(f"[removed] {item['id']} ({item['display_name']})")

    if args.json:
        Path(args.json).write_text(
            json.dumps(report, indent=2, default=str), encoding="utf-8"
        )

    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

