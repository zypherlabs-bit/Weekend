"""Dry-run a migration against the live database inside a rolled-back transaction.

Applies the migration SQL and an optional probe statement in one transaction
that is rolled back, so nothing is persisted. Useful for "does this even
compile, and does it route correctly" before touching production.

Usage:
    python tool/dry_run_migration.py <migration.sql> [probe.sql]
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
TOKEN_FILE = pathlib.Path(os.environ.get("TEMP", ".")) / "sbp_token.txt"


def token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if t:
        return t
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def sql(query: str) -> list:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        body = resp.read().decode()
    return json.loads(body) if body.strip() else []


def snapshot(sig_like: str) -> list:
    return sql(
        "select pg_get_function_identity_arguments(p.oid) as args, "
        "length(pg_get_functiondef(p.oid)) as len, "
        "pg_get_function_result(p.oid) as ret "
        "from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
        f"where n.nspname='public' and p.proname='search_profiles' order by 1"
    )


def main() -> int:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    migration = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").replace("\r\n", "\n")
    probe = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""

    before = snapshot("search_profiles")

    statement = "begin;\n" + migration + ("\n" + probe if probe else "") + "\nrollback;"
    print(f"=== dry run {sys.argv[1]} (rolled back) ===")
    try:
        rows = sql(statement)
        print("  migration executed cleanly; probe result:",
              json.dumps(rows)[:300])
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        print(f"  HTTP {exc.code}")
        print("  " + detail[:700].replace("\n", "\n  "))

    after = snapshot("search_profiles")
    same = [(b.get("args"), b.get("len"), b.get("ret")) for b in before] == \
           [(a.get("args"), a.get("len"), a.get("ret")) for a in after]
    print(f"  live state unchanged after rollback: {same}")
    for row in after:
        print(f"    {row['args'][:58]}... len={row['len']}")
    return 0 if same else 1


if __name__ == "__main__":
    sys.exit(main())
