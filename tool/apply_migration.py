"""Apply a migration file to a Supabase project through the Management API.

The `POST /database/query` endpoint executes ONE statement per request and does
not understand dollar-quoted bodies (`$$ ... $$`), so posting a whole file fails
with a syntax error at the first `declare`. This splitter is dollar-quote aware
and submits each top-level statement in order, stopping at the first failure and
reporting the exact statement that broke.

Usage:
    python tool/apply_migration.py supabase/migrations/025_profile_experience_and_mfa_recovery.sql

The management token is read from --token, $SUPABASE_ACCESS_TOKEN, or
%TEMP%\\sbp_token.txt (the machine-local token cache the repo's own
tool/live_probe.py already relies on). The token is never printed.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
QUERY_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"


def read_token(explicit: str | None) -> str:
    if explicit:
        return explicit.strip()
    env = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if env:
        return env.strip()
    cached = pathlib.Path(os.environ.get("TEMP", ".")) / "sbp_token.txt"
    if cached.exists():
        return cached.read_text(encoding="utf-8").strip()
    raise SystemExit(
        "No Supabase management token. Pass --token, set "
        "SUPABASE_ACCESS_TOKEN, or create %TEMP%\\sbp_token.txt."
    )


def split_statements(sql: str) -> list[str]:
    """Split a SQL script into top-level statements.

    Dollar-quoted bodies ($$ ... $$ and $tag$ ... $tag$) are kept intact, as are
    single-quoted strings, double-quoted identifiers and both comment styles.
    """
    statements: list[str] = []
    buf: list[str] = []
    i = 0
    n = len(sql)
    dollar_tag: str | None = None

    while i < n:
        ch = sql[i]

        if dollar_tag is None and ch == "-" and sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j == -1 else j
            buf.append(sql[i:j])
            i = j
            continue

        if dollar_tag is None and ch == "/" and sql.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if sql.startswith("/*", i):
                    depth += 1
                    i += 2
                elif sql.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue

        if dollar_tag is None and ch == "$":
            end = sql.find("$", i + 1)
            if end != -1:
                tag = sql[i + 1 : end]
                if tag == "" or tag.replace("_", "").isalnum():
                    dollar_tag = "$" + tag + "$"
                    buf.append(dollar_tag)
                    i = end + 1
                    continue

        if ch == "'" and dollar_tag is None:
            buf.append(ch)
            i += 1
            while i < n:
                buf.append(sql[i])
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        buf.append(sql[i + 1])
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue

        if ch == '"' and dollar_tag is None:
            buf.append(ch)
            i += 1
            while i < n:
                buf.append(sql[i])
                if sql[i] == '"':
                    i += 1
                    break
                i += 1
            continue

        if dollar_tag is not None and sql.startswith(dollar_tag, i):
            buf.append(dollar_tag)
            i += len(dollar_tag)
            dollar_tag = None
            continue

        if ch == ";" and dollar_tag is None:
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def run(token: str, sql: str) -> tuple[int, str]:
    data = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(QUERY_URL, data=data, method="POST")
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def read_sql(path: str) -> str:
    """Read a SQL file, tolerating a UTF-8 BOM from Windows editors."""
    return pathlib.Path(path).read_text(encoding="utf-8-sig")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--token", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = read_token(args.token)
    sql = read_sql(args.path)
    statements = split_statements(sql)
    print(f"{args.path}: {len(statements)} statements")

    if args.dry_run:
        for i, s in enumerate(statements, 1):
            print(f"  {i:>2}. {ascii(' '.join(s.split())[:110])}")
        return 0

    for i, stmt in enumerate(statements, 1):
        head = ascii(" ".join(stmt.split())[:90])
        status, body = run(token, stmt)
        # The Management API answers 200 for DML and 201 for a successful
        # statement executed through the query planner; both are success.
        if status not in (200, 201):
            print(f"FAIL at statement {i}: {head}")
            print(f"HTTP {status}: {body[:1500]}")
            return 1
        print(f"  ok {i:>2}. (HTTP {status}) {head}")
    print("migration applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
