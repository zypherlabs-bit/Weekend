"""
Weekend -- decisive "is migration 028 live?" probe.

PostgREST answers PGRST202 for BOTH of two very different situations:

  (a) the function genuinely does not exist in the database, and
  (b) the function exists but no overload accepts the argument shape sent.

Calling with {} therefore proves nothing. This probe calls each watched
function with the EXACT named parameter list declared in the migration files,
which is the only way to tell "absent" apart from "signature mismatch" --
and therefore the only way to prove whether 028 is applied to production.

The two functions that exist ONLY if 028 applied are:
  is_adult_user(uuid)                    -- created by 028
  enforce_adult_date_of_birth()         -- created by 028 (trigger fn)
plus the ADDED PARAMETER on record_like(p_target_id, p_is_stand_out):
  026 declared record_like(p_target_id uuid) only.

Uses only the public anon key; never prints a token or a UUID.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

# (label, rpc name, body) -- bodies use the exact declared signatures.
CALLS = [
    ("028 marker", "is_adult_user", {"p_user_id": "00000000-0000-0000-0000-000000000000"}),
    ("026 base", "get_received_likes", {"p_user_id": "00000000-0000-0000-0000-000000000000"}),
    ("026 base", "get_matches_for_user", {"p_user_id": "00000000-0000-0000-0000-000000000000"}),
    ("026 base", "notification_unread_count", {}),
    ("026 base", "ensure_interest", {"p_name": "wkd-probe-x"}),
    ("026/028", "record_like", {"p_target_id": "00000000-0000-0000-0000-000000000000",
                                "p_is_stand_out": False}),
    ("026/028", "record_pass", {"p_target_id": "00000000-0000-0000-0000-000000000000"}),
    ("023", "minimum_profile_photos", {}),
    ("023", "approved_photo_count", {"p_user_id": "00000000-0000-0000-0000-000000000000"}),
    ("023", "get_my_profile_completion", {"p_user_id": "00000000-0000-0000-0000-000000000000"}),
    ("023", "search_profiles", {"p_limit": 1}),
    ("023/027", "get_nearby_profiles", {"p_lat": 0.0, "p_lng": 0.0,
                                        "p_radius_km": 5, "p_limit": 1}),
    ("008", "get_ad_for_user", {}),
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


def rpc(base: str, anon: str, fn: str, body: dict):
    req = urllib.request.Request(f"{base}/rest/v1/rpc/{fn}",
                                 data=json.dumps(body).encode(), method="POST")
    req.add_header("apikey", anon)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + anon)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return 0, f"{type(e).__name__}: {e}"


def classify(status: int, body: str) -> str:
    """Map an HTTP answer to a human verdict about function existence."""
    if status == 0:
        return "NETWORK-ERROR"
    if status == 404 and "PGRST202" in body:
        return "ABSENT (not in schema cache)"
    if status in (401, 403):
        return "EXISTS but not callable by anon (permission denied)"
    if status == 400:
        # A named-parameter/argument complaint proves the function was FOUND.
        return "EXISTS (argument/permission complaint from the function)"
    return f"reachable (HTTP {status})"


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    print(f"=== Migration-existence probe against {base} ===")
    print("(calling with the EXACT parameter names declared in the migrations)\n")
    for label, fn, body in CALLS:
        st, b = rpc(base, anon, fn, body)
        verdict = classify(st, b)
        snippet = " ".join(b.split())[:110]
        print(f"  [{label:<9}] {fn:<24} HTTP {st:<4} {verdict}")
        if verdict.startswith("ABSENT"):
            print(f"                 {snippet}")
    print("\n=== probe complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())