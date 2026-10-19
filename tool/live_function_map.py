"""
Weekend -- enumerate the ACTUAL live function catalogue via PostgREST.

PostgREST's PGRST202 error carries a `hint` field that fuzzy-matches the
requested name against the real schema cache. That makes the cache
enumerable without any privileged credential: ask for a nonsense name and
read back what the server believes exists.

The 404/401 split is the existence oracle:
  404 PGRST202 -> not in the schema cache -> the function does NOT exist
  401 / 403    -> resolved, then refused     -> the function DOES exist
  400/200/...  -> reached the function body   -> the function DOES exist

This script maps every function the migrations create onto that oracle so the
applied/not-applied line can be stated with evidence rather than assumption.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

# name -> the migration that creates it (for the report)
EXPECTED = {
    # 001-003 core
    "get_user_profile": "003", "update_user_profile": "003",
    "get_user_photos": "003", "record_swipe": "003",
    # 008 ads
    "get_ad_for_user": "008", "record_ad_event": "008", "compute_crossed_paths": "008",
    # 023 profile completeness / discovery
    "minimum_profile_photos": "023", "approved_photo_count": "023",
    "sync_dating_profile_activation": "023", "get_my_profile_completion": "023",
    "search_profiles": "023", "get_nearby_profiles": "023", "mark_profile_deleted": "023",
    # 026 dating platform
    "enforce_message_rules": "026", "sync_profile_completion": "026",
    "get_matches_for_user": "026", "record_like": "026", "record_pass": "026",
    "unmatch_match": "026", "get_received_likes": "026", "notify_on_message": "026",
    "get_notifications": "026", "mark_all_notifications_read": "026",
    "notification_unread_count": "026", "submit_report": "026", "ensure_interest": "026",
    # 027 device tokens / mode queries
    "record_device_token": "027", "get_device_tokens_for_user": "027",
    "get_nearby_profiles_v2": "027",
    # 028 ADULTS ONLY
    "enforce_adult_date_of_birth": "028", "freeze_date_of_birth": "028",
    "is_adult_user": "028", "check_mutual_like": "028",
    # account deletion
    "delete_user_account": "009", "assert_self": "009",
}


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


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    print(f"=== Live function-existence map for {base} ===\n")

    # Probe with a body carrying the required-looking param names. We do not
    # care whether the CALL succeeds; we only care whether the function is
    # resolved at all.
    results = {}
    for fn, mig in sorted(EXPECTED.items(), key=lambda kv: (kv[1], kv[0])):
        st, body = rpc(base, anon, fn, {"p_user_id": "00000000-0000-0000-0000-000000000000",
                                        "p_target_id": "00000000-0000-0000-0000-000000000000",
                                        "p_match_id": "00000000-0000-0000-0000-000000000000",
                                        "p_name": "wkd", "p_lat": 0.0, "p_lng": 0.0,
                                        "p_limit": 1, "p_is_stand_out": False})
        exists = not (st == 404 and "PGRST202" in body)
        results[fn] = (mig, exists, st)

    by_mig: dict = {}
    for fn, (mig, exists, st) in results.items():
        by_mig.setdefault(mig, []).append((fn, exists, st))

    print(f"{'migration':<11} {'present':<9} {'absent':<8} verdict")
    print("-" * 74)
    for mig in sorted(by_mig):
        items = by_mig[mig]
        present = [f for f, e, _ in items if e]
        absent = [f for f, e, _ in items if not e]
        state = "APPLIED" if present and not absent else (
            "NOT APPLIED" if absent and not present else "PARTIAL / SIGNATURE MISMATCH")
        print(f"{mig:<11} {len(present):<9} {len(absent):<8} {state}")

    print("\n--- detail ---")
    for mig in sorted(by_mig):
        for fn, exists, st in sorted(by_mig[mig]):
            flag = "EXISTS " if exists else "ABSENT "
            print(f"  {flag} [{mig}] {fn}  (HTTP {st})")

    # Direct answer for the launch gate.
    adult_mig = [f for f, (m, e, _) in results.items() if m == "028" and e]
    print("\n=== launch-gate conclusion ===")
    if not adult_mig:
        print("  MIGRATION 028 IS NOT APPLIED TO PRODUCTION.")
        print("  is_adult_user / enforce_adult_date_of_birth / freeze_date_of_birth")
        print("  are all absent, so the adults-only guarantee does NOT exist in the")
        print("  live database. Every age-restriction claim is therefore FAIL.")
    else:
        print(f"  028 functions present: {adult_mig}")
    return 0


if __name__ == "__main__":
    sys.exit(main())