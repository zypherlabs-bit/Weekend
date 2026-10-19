"""Focused, fully-logged existence check for the launch-critical functions."""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ZERO = "00000000-0000-0000-0000-000000000000"

CASES = [
    # (label, function, exact body)
    ("028 ONLY", "is_adult_user", {"p_user_id": ZERO}),
    ("028 ONLY", "enforce_adult_date_of_birth", {}),
    ("028 ONLY", "freeze_date_of_birth", {}),
    ("028 ONLY", "check_mutual_like", {}),
    ("028 sig", "record_like", {"p_target_id": ZERO, "p_is_stand_out": False}),
    ("026 sig", "record_like", {"p_target_id": ZERO}),
    ("028 sig", "search_profiles", {
        "p_user_id": ZERO, "p_genders": None, "p_age_min": 18, "p_age_max": 65,
        "p_max_distance_km": None, "p_city": None,
        "p_relationship_intents": None, "p_interests": None,
        "p_languages": None, "p_lifestyle": None, "p_location_mode": "global",
        "p_page": 1, "p_page_size": 1}),
    ("023 sig", "search_profiles", {
        "p_user_id": ZERO, "p_genders": None, "p_age_min": 18, "p_age_max": 65,
        "p_max_distance_km": None, "p_city": None,
        "p_relationship_intents": None, "p_interests": None,
        "p_languages": None, "p_lifestyle": None, "p_location_mode": "global",
        "p_page": 1, "p_page_size": 1}),
    ("027 sig", "get_nearby_profiles", {
        "p_user_id": ZERO, "p_limit": 1, "p_offset": 0,
        "p_max_distance_km": 5.0, "p_preferred_genders": None,
        "p_age_min": 18, "p_age_max": 65, "p_discovery_mode": "global"}),
    ("026 zero-arg", "notification_unread_count", {}),
    ("026", "get_received_likes", {"p_user_id": ZERO}),
    ("026", "submit_report", {"p_target_user_id": ZERO, "p_reason": "probe",
                              "p_details": "probe"}),
    ("023 zero-arg", "minimum_profile_photos", {}),
    ("023", "approved_photo_count", {"p_user_id": ZERO}),
    ("009", "delete_user_account", {}),
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


def rpc(base, anon, fn, body):
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
    print(f"=== Focused existence check: {base} ===\n")
    for label, fn, body in CASES:
        st, txt = rpc(base, anon, fn, body)
        if st == 404 and "PGRST202" in txt:
            verdict = "ABSENT"
        elif st in (401, 403):
            verdict = "EXISTS (anon not permitted)"
        elif st == 200:
            verdict = "EXISTS (executed)"
        elif st == 400:
            verdict = "EXISTS (argument/permission error in body)"
        else:
            verdict = f"? HTTP {st}"
        print(f"[{label:<14}] {fn:<28} -> {verdict}")
        if verdict == "ABSENT":
            try:
                print("      detail:", json.loads(txt).get("details", "")[:190])
            except Exception:  # noqa: BLE001
                print("      detail:", " ".join(txt.split())[:190])
    return 0


if __name__ == "__main__":
    sys.exit(main())