"""Apply a local migration file to the LIVE project over the Management API.

Why this exists: on some networks the Supabase Postgres ports (5432/6543) are
firewalled, so `supabase db push` cannot reach the database. The Management API
HTTPS endpoint POST /v1/projects/{ref}/database/query *is* reachable, so this
script reproduces what `db push` does for one migration:

  begin;
  <migration file, LF-normalised>          -- the migration itself
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values (<version>, <name>, array[<file text>]);   -- CLI-compatible history row
  commit;

Both the DDL and the history row land in ONE transaction, so a failure leaves
neither behind. Refuses to run a version that is already recorded.

Usage:  python tool/apply_migration_via_api.py supabase/migrations/031_*.sql ...
Token:  read from SUPABASE_ACCESS_TOKEN, or the temp file below.
        The token is never printed.
"""

from __future__ import annotations

import glob
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
TOKEN_FILE = pathlib.Path(os.environ.get("TEMP", ".")) / "sbp_token.txt"
ROOT = pathlib.Path(__file__).resolve().parents[1]


def token() -> str:
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if tok:
        return tok
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text(encoding="utf-8").strip()
    sys.exit("no token: set SUPABASE_ACCESS_TOKEN or write " + str(TOKEN_FILE))


def sql(query: str) -> list:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {exc.code}: {detail[:1500]}") from None
    return json.loads(body) if body.strip() else []


def already_applied(version: str) -> bool:
    rows = sql(
        "select version from supabase_migrations.schema_migrations "
        f"where version = '{version}'"
    )
    return bool(rows)


def quote(text: str) -> str:
    tag = "$wkmig$"
    while tag in text:
        tag = tag[:-1] + "x$"
    return f"{tag}{text}{tag}::text"


def main() -> int:
    patterns = sys.argv[1:]
    if not patterns:
        sys.exit("usage: apply_migration_via_api.py <migration file> [...]")

    files: list[pathlib.Path] = []
    for pat in patterns:
        files.extend(sorted(pathlib.Path(p) for p in glob.glob(pat)))

    for path in files:
        version, name = path.stem.split("_", 1)
        if already_applied(version):
            print(f"[skip] {version} already recorded remotely")
            continue

        body = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        stmt = (
            "begin;\n"
            + body
            + "\n\ninsert into supabase_migrations.schema_migrations "
            "(version, name, statements) values "
            f"('{version}', '{name}', array[{quote(body)}]);\n"
            "commit;"
        )
        print(f"[apply] {version} {name} ({len(body)} chars) ...", flush=True)
        sql(stmt)

        # verify both effects really landed
        rows = sql(
            "select version, name, length(statements[1]) as len "
            "from supabase_migrations.schema_migrations "
            f"where version = '{version}'"
        )
        if not rows:
            raise RuntimeError(f"{version} applied but history row missing")
        print(f"        recorded: {rows[0]}")

    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
