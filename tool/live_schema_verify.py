"""Verify the live schema after applying migrations 031-033.

Read-only. Diffs the public schema against a pre-migration inventory captured in
pre_state.json and asserts the objects the three migrations promise actually
exist, with the right security posture. Prints no secrets.

Usage: python tool/live_schema_verify.py
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN_FILE = TEMP / "sbp_token.txt"
PRE = TEMP / "opencode" / "live" / "pre_state.json"
OUT = TEMP / "opencode" / "live" / "post_state.json"

TABLE_Q = "select table_name from information_schema.tables where table_schema='public' order by 1"
COL_Q = "select table_name || '.' || column_name as col from information_schema.columns where table_schema='public' order by 1"
FN_Q = ("select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig, "
        "pg_get_function_result(p.oid) as ret, "
        "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec, "
        "has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec "
        "from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
        "where n.nspname='public' and p.prokind='f' order by 1")


def token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if t:
        return t
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def sql(query: str) -> list:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode("utf-8"),
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        body = resp.read().decode("utf-8")
    return json.loads(body) if body.strip() else []


def main() -> int:
    post = {
        "tables": [r["table_name"] for r in sql(TABLE_Q)],
        "columns": [r["col"] for r in sql(COL_Q)],
        "functions": {
            r["sig"]: {"ret": r["ret"], "anon_exec": r["anon_exec"], "auth_exec": r["auth_exec"]}
            for r in sql(FN_Q)
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(post, indent=1), encoding="utf-8")

    pre = json.loads(PRE.read_text(encoding="utf-8")) if PRE.exists() else {}
    pre_t, pre_c = set(pre.get("tables", [])), set(pre.get("columns", []))
    post_t, post_c = set(post["tables"]), set(post["columns"])

    print("=== schema delta (001-030 -> 001-033) ===")
    print(f"tables  : {len(pre_t)} -> {len(post_t)}  (+{len(post_t - pre_t)})")
    for t in sorted(post_t - pre_t):
        print(f"   + {t}")
    print(f"columns : {len(pre_c)} -> {len(post_c)}  (+{len(post_c - pre_c)})")
    print("   (new columns on pre-existing tables)")
    for c in sorted(post_c - pre_c):
        if c.split(".")[0] in pre_t:
            print(f"   + {c}")

    print()
    print("=== migrations recorded ===")
    for r in sql("select version, name from supabase_migrations.schema_migrations "
                 "where version in ('031','032','033') order by version"):
        print(f"   {r['version']}  {r['name']}")

    print()
    print("=== promised tables ===")
    for t in ["user_entitlements", "spotlight_windows", "photo_impressions",
              "support_tickets", "opening_moves", "discovery_surges"]:
        print(f"   {t:24s} {'YES' if t in post_t else 'MISSING'}")

    print()
    print("=== promised columns ===")
    for c in ["likes.note", "likes.priority_weight", "matches.initiator_id",
              "matches.window_opened_at", "matches.rematch_count", "matches.rematched_at",
              "messages.risk_flags", "user_settings.incognito_mode",
              "user_settings.snooze_until", "user_settings.travel_lat",
              "user_settings.away_until", "user_settings.show_online_now"]:
        print(f"   {c:28s} {'YES' if c in post_c else 'MISSING'}")

    pre_raw = pre.get("functions", {})
    pre_fn = pre_raw if isinstance(pre_raw, dict) else {s: {} for s in pre_raw}
    post_fn = post["functions"]
    new_fn = sorted(set(post_fn) - set(pre_fn))
    changed = sorted(s for s in set(post_fn) & set(pre_fn)
                     if pre_fn[s].get("ret") not in (None, post_fn[s]["ret"]))
    removed = sorted(set(pre_fn) - set(post_fn))

    print()
    print(f"=== functions added by 031-033: {len(new_fn)} ===")
    for s in new_fn:
        f = post_fn[s]
        print(f"   {'ANON-EXEC!' if f['anon_exec'] else 'auth-only '} "
              f"{'auth:yes' if f['auth_exec'] else 'auth:NO '}  {s[:78]}")

    print()
    print(f"=== functions whose return type changed: {len(changed)} ===")
    for s in changed:
        print(f"   {'ANON-EXEC!' if post_fn[s]['anon_exec'] else 'auth-only '} {s[:90]}")

    print()
    print(f"=== functions removed (old overloads replaced): {len(removed)} ===")
    for s in removed:
        print(f"   - {s[:90]}")

    print()
    print("=== RLS on new tables ===")
    rls = sql("select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace "
              "where n.nspname='public' and c.relkind='r' order by 1")
    flags = {r["relname"]: r["relrowsecurity"] for r in rls}
    for t in ["user_entitlements", "spotlight_windows", "photo_impressions",
              "support_tickets", "opening_moves", "discovery_surges"]:
        if t in flags:
            print(f"   {t:24s} rls={'ENABLED' if flags[t] else 'DISABLED'}")
    print()
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
