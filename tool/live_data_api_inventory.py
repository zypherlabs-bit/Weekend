"""
Weekend -- LIVE, READ-ONLY Data API inventory (Phase 3/4 evidence helper).

Answers, over HTTPS only (no psql / port 5432 needed):

  [A] Which tables does the PostgREST schema cache expose, and can the ANON
      role see rows in them? Uses GET ?limit=1 + Prefer: count=exact, so the
      Content-Range reports how many rows are visible to anonymous callers.
  [B] Which RPCs exist? Only NON-MUTATING functions are probed, each with the
      exact parameter names the app/migrations declare:
        404 PGRST202 -> absent from schema cache (or signature mismatch)
        401 / 403    -> EXISTS, permission denied to anon
        400 / 200    -> EXISTS (argument complaint / success)
      Mutating functions (record_like, ensure_interest, delete_user_account,
      ...) are deliberately NEVER called here.
  [C] PostGIS presence probes: spatial_ref_sys exposure through the Data API
      and zero-argument postgis_*() functions.

Uses only the public anon key from .env. Prints no secrets, no emails, no
user UUIDs (only the all-zero probe UUID). Read-only by construction.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ZERO = "00000000-0000-0000-0000-000000000000"

# Tables created by supabase/migrations (application tables) plus the
# PostGIS reference table the Security Advisor flagged.
APP_TABLES = [
    "ad_campaigns", "ad_clicks", "ad_config", "ad_events", "ad_impressions",
    "advertisements", "blocks", "conversation_members", "conversations",
    "crossed_paths", "crossed_paths_log", "device_tokens", "favorite_places",
    "interests", "likes", "matches", "messages", "mfa_recovery_codes",
    "moderation_events", "notifications", "passes", "plan_participants",
    "plans", "preferences", "profile_photos", "profile_requirements",
    "profiles", "referral_events", "referrals", "reports", "user_interests",
    "user_location_buckets", "user_settings", "verification_requests",
]
EXTENSION_TABLES = ["spatial_ref_sys", "geography_columns", "geometry_columns"]

# (label, rpc, body) -- read-only functions only, exact declared parameter names.
RPCS = [
    # sanity: proven-working zero-arg functions
    ("023 sanity", "minimum_profile_photos", {}),
    ("025 sanity", "maximum_profile_photos", {}),
    # 003 / 008 markers
    ("008", "get_ad_for_user", {}),
    ("008 retry", "get_ad_for_user", {"p_user_id": ZERO}),
    # 023 / 028 discovery markers (exact app call shape)
    ("023", "search_profiles", {"p_user_id": ZERO, "p_limit": 1}),
    ("023", "get_my_profile_completion", {"p_user_id": ZERO}),
    ("023", "approved_photo_count", {"p_user_id": ZERO}),
    ("023/027", "get_nearby_profiles", {
        "p_user_id": ZERO, "p_limit": 1, "p_offset": 0,
        "p_max_distance_km": 1.0, "p_preferred_genders": [],
        "p_age_min": 18, "p_age_max": 65, "p_discovery_mode": "nearby",
    }),
    # 026 dating-platform markers
    ("026", "get_matches_for_user", {"p_user_id": ZERO, "p_limit": 1, "p_offset": 0}),
    ("026", "get_received_likes", {"p_user_id": ZERO}),
    ("026", "get_notifications", {"p_limit": 1, "p_offset": 0}),
    ("026", "notification_unread_count", {}),
    # 027 device tokens
    ("027", "get_device_tokens_for_user", {"p_user_id": ZERO}),
    # 028 adults-only marker (read-only predicate)
    ("028", "is_adult_user", {"p_user_id": ZERO}),
    # 009/017 helpers
    ("009", "assert_self", {"p_user_id": ZERO}),
    ("017", "get_referral_stats", {"p_user_id": ZERO}),
    # PostGIS zero-arg probes
    ("postgis", "postgis_version", {}),
    ("postgis", "postgis_lib_version", {}),
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


def call(base: str, anon: str, path: str, *, method: str = "GET",
         body=None, params: str = "", exact_count: bool = False):
    url = f"{base}/{path}{params}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", anon)
    req.add_header("Authorization", "Bearer " + anon)
    req.add_header("Content-Type", "application/json")
    if exact_count:
        req.add_header("Prefer", "count=exact")
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return r.status, r.read().decode("utf-8", "replace"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers
    except Exception as e:  # noqa: BLE001
        return 0, f"{type(e).__name__}: {e}", {}


def snippet(text: str, n: int = 120) -> str:
    return " ".join((text or "").split())[:n]


def table_verdict(status: int, body: str) -> str:
    if status == 0:
        return "NETWORK-ERROR"
    if status == 404:
        return "ABSENT from schema cache"
    if status in (401, 403):
        return "EXISTS, denied to anon"
    if status == 200:
        return "READABLE by anon"
    return f"HTTP {status}"


def rpc_verdict(status: int, body: str) -> str:
    if status == 0:
        return "NETWORK-ERROR"
    if status == 404 and "PGRST202" in body:
        return "ABSENT or signature mismatch"
    if status in (401, 403):
        return "EXISTS, denied to anon"
    if status == 400:
        return "EXISTS (argument complaint)"
    return f"reachable (HTTP {status})"


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    print(f"=== READ-ONLY Data API inventory for {base} ===")

    # ---- [A] tables -------------------------------------------------------
    print("\n[A] tables visible to the anon role (limit=1, count=exact)")
    print(f"    {'table':<24} {'status':<7} {'anon-rows':<10} verdict")
    readable: list[str] = []
    for t in APP_TABLES + EXTENSION_TABLES:
        st, body, headers = call(
            base, anon, f"rest/v1/{t}",
            params="?select=*&limit=1", exact_count=True,
        )
        cr = headers.get("Content-Range", "") if headers else ""
        anon_rows = cr.split("/")[-1] if cr else "?"
        verdict = table_verdict(st, body)
        if verdict == "READABLE by anon":
            readable.append(t)
        marker = " *" if t in EXTENSION_TABLES else ""
        print(f"    {t:<24} {st:<7} {anon_rows:<10} {verdict}{marker}")
        if verdict == "READABLE by anon" and t in EXTENSION_TABLES:
            print(f"       sample: {snippet(body, 140)}")

    # ---- [B] RPCs ---------------------------------------------------------
    print("\n[B] read-only RPC existence probes (exact parameter names)")
    for label, fn, body in RPCS:
        st, b, _ = call(base, anon, f"rest/v1/rpc/{fn}",
                        method="POST", body=body)
        verdict = rpc_verdict(st, b)
        print(f"    [{label:<11}] {fn:<28} HTTP {st:<4} {verdict}")
        if verdict.startswith("EXISTS") or verdict.startswith("reachable"):
            print(f"        {snippet(b)}")

    # ---- summary ----------------------------------------------------------
    print("\n=== summary ===")
    ext_readable = [t for t in readable if t in EXTENSION_TABLES]
    app_readable = [t for t in readable if t in APP_TABLES]
    print(f"    app tables readable by ANON (any rows): {app_readable or 'none'}")
    print(f"    extension tables readable by ANON     : {ext_readable or 'none'}")
    print("    (a table can be readable-but-empty when RLS returns 0 rows;")
    print("     anon-rows above is the RLS-filtered count visible without auth)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
