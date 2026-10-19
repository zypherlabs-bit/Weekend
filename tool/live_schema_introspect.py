"""
Weekend -- LIVE PostgREST schema introspection via the public OpenAPI spec.

`GET /rest/v1/` with `Accept: application/openapi+json` returns the schema
PostgREST is actually serving. This is the authoritative answer to "which
functions and tables really exist in production", and it distinguishes:

  * function genuinely absent from the database, vs
  * function present in the database but missing from a STALE schema cache
    (PostgREST answers PGRST202 in both cases, which is why the naive RPC
    probe on its own is not conclusive).

Uses only the public anon key. Prints no secret values.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

WATCHED_FUNCS = [
    "search_profiles", "get_nearby_profiles", "record_like", "check_mutual_like",
    "delete_user_account", "get_ad_for_user", "record_ad_event",
    "compute_crossed_paths", "get_photo_urls", "assert_self",
    "handle_new_user", "enforce_adult_date_of_birth",
    "record_device_token", "unmatch_user", "block_user", "report_user",
]

WATCHED_TABLES = [
    "profiles", "profile_photos", "likes", "matches", "messages",
    "user_settings", "device_tokens", "advertisements", "ad_config",
    "reports", "blocked_users", "crossed_paths",
]


def env_vars() -> dict:
    out: dict = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    url = f"{base}/rest/v1/"
    req = urllib.request.Request(url, method="GET")
    req.add_header("apikey", anon)
    req.add_header("Authorization", "Bearer " + anon)
    req.add_header("Accept", "application/openapi+json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            status = r.status
            spec = json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        print(f"OpenAPI fetch FAILED -> HTTP {e.code}")
        print("  (a 401/403 here means the anon role cannot read the schema)")
        return 2
    except Exception as e:  # noqa: BLE001
        print(f"OpenAPI fetch FAILED -> {type(e).__name__}: {e}")
        return 2

    print(f"=== PostgREST OpenAPI spec fetched -> HTTP {status} ===\n")

    defs = spec.get("definitions", {})
    paths = spec.get("paths", {})

    print(f"tables exposed in schema cache : {len(defs)}")
    print(f"paths in schema cache          : {len(paths)}\n")

    print("[A] tables")
    for t in WATCHED_TABLES:
        hit = t in defs
        print(f"    {t:<20} {'present' if hit else 'ABSENT'}")

    print("\n[B] RPC functions (POST /rpc/<name> paths)")
    rpc_names = set()
    for p in paths:
        if p.startswith("/rpc/"):
            rpc_names.add(p[len("/rpc/"):])
    print(f"    total rpcs exposed: {len(rpc_names)}")
    for fn in WATCHED_FUNCS:
        print(f"    {fn:<30} {'present' if fn in rpc_names else 'ABSENT'}")

    print("\n[C] every RPC actually exposed in production")
    for fn in sorted(rpc_names):
        print(f"    - {fn}")

    print("\n=== introspection complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())