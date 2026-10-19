"""Probe the live backend as an AUTHENTICATED synthetic account.

Anon-key probes cannot distinguish "function absent" from "function exists but
EXECUTE revoked from anon". This script logs in the dedicated synthetic probe
account (tool/create_probe_account.py) and calls every RPC the Flutter client
actually calls, with the same parameter names the client sends.

Classification per call:
  LIVE      2xx - the RPC ran; row/value summary reported
  GUARDED   4xx from PostgREST *other than* 404 - the RPC exists and reacted
            (validation, permission, no-such-target). The body is reported.
  ABSENT    404 / PGRST202 - the RPC does not exist at this signature
  DENIED    401/403 - exists but this role may not execute it
  FAULT     5xx - the RPC exists and raised a server-side error

Safety: calls that would create or mutate *other* users' data are issued with a
non-existent target id on purpose, so the only possible outcome is a guard
error. Calls that touch only the probe account's own rows are issued normally.
Reads never mutate anything.

Usage:  python tool/authenticated_probe.py [--json]
Writes: tool/_auth_probe_results.json
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NIL = "00000000-0000-0000-0000-000000000000"


def load_env() -> dict:
    env = {}
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


ENV = load_env()
BASE = ENV["SUPABASE_URL"].rstrip("/")
ANON = ENV["SUPABASE_ANON_KEY"]
EMAIL = ENV.get("PROBE_EMAIL", "")
PASSWORD = ENV.get("PROBE_PASSWORD", "")


def post(path: str, payload, jwt=None):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("apikey", ANON)
    if jwt:
        req.add_header("Authorization", "Bearer " + jwt)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode() or "{}"
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            return exc.code, json.loads(raw)
        except json.JSONDecodeError:
            return exc.code, raw


def rpc(name, params, jwt, method="POST"):
    return post(f"/rest/v1/rpc/{name}", params or {}, jwt)


def summarize(res):
    if isinstance(res, list):
        return f"rows={len(res)}"
    if isinstance(res, dict):
        if "code" in res or "message" in res:
            msg = str(res.get("message") or res.get("code"))
            return msg[:160]
        return json.dumps(res)[:160]
    return str(res)[:160]


def classify(status, res):
    if status in (200, 201, 204):
        return "LIVE"
    if status == 404 or (isinstance(res, dict) and res.get("code") == "PGRST202"):
        return "ABSENT"
    if status in (401, 403):
        return "DENIED"
    if status >= 500:
        return "FAULT"
    return "GUARDED"


def probes(uid):
    """(label, rpc, params, writes_other_user_data)"""
    return [
        # --- discovery -------------------------------------------------
        ("discovery/get_nearby_profiles", "get_nearby_profiles", {
            "p_user_id": uid, "p_limit": 5, "p_offset": 0, "p_max_distance_km": 20000,
            "p_preferred_genders": [], "p_age_min": 18, "p_age_max": 99,
            "p_discovery_mode": "nearby", "p_last_active_hours": None}, False),
        ("discovery/search_profiles (21-arg, hardened)", "search_profiles", {
            "p_user_id": uid, "p_limit": 5, "p_offset": 0, "p_max_distance_km": 20000,
            "p_search_lat": None, "p_search_lon": None, "p_search_city": None,
            "p_genders": None, "p_age_min": 18, "p_age_max": 99, "p_interested_in": None,
            "p_relationship_intents": None, "p_cities": None, "p_interests": None,
            "p_languages": None, "p_smoking": None, "p_drinking": None, "p_exercise": None,
            "p_children": None, "p_pets": None, "p_include_dealt": False}, False),
        ("search/search_profiles (13-arg, used by search screen)", "search_profiles", {
            "p_user_id": uid, "p_genders": None, "p_age_min": 18, "p_age_max": 99,
            "p_max_distance_km": 20000, "p_city": None, "p_relationship_intents": None,
            "p_interests": None, "p_languages": None, "p_lifestyle": None,
            "p_location_mode": "nearby", "p_page": 1, "p_page_size": 5}, False),
        ("discovery/get_surge_state", "get_surge_state", {}, False),
        # --- engagement / entitlements ---------------------------------
        ("engagement/activate_spotlight", "activate_spotlight", {}, False),
        ("engagement/get_my_spotlight", "get_my_spotlight", {}, False),
        ("engagement/get_my_photo_insights", "get_my_photo_insights", {}, False),
        ("discovery/record_photo_impressions", "record_photo_impressions",
         {"p_photo_ids": []}, False),
        # --- likes / matches -------------------------------------------
        ("likes/get_received_likes", "get_received_likes", {"p_limit": 5, "p_offset": 0}, False),
        ("matches/get_matches_for_user", "get_matches_for_user",
         {"p_user_id": uid, "p_limit": 5, "p_offset": 0}, False),
        ("likes/record_like (nil target -> expect guard)", "record_like",
         {"p_target_id": NIL, "p_is_stand_out": False, "p_note": None}, True),
        ("likes/record_pass (nil target -> expect guard)", "record_pass",
         {"p_target_id": NIL}, True),
        ("matches/extend_match (nil match -> expect guard)", "extend_match",
         {"p_match_id": NIL}, True),
        ("matches/unmatch_match (nil match -> expect guard)", "unmatch_match",
         {"p_match_id": NIL}, True),
        ("chat/get_conversation_away_note (nil conv -> expect guard)",
         "get_conversation_away_note", {"p_conversation_id": NIL}, True),
        # --- privacy modes --------------------------------------------
        ("privacy/set_privacy_mode", "set_privacy_mode",
         {"p_mode": "incognito", "p_enabled": False, "p_snooze_hours": 0}, False),
        ("privacy/set_away_status", "set_away_status", {"p_message": "", "p_hours": 0}, False),
        ("privacy/set_travel_location (null coords -> expect guard)", "set_travel_location",
         {"p_city": "", "p_lat": None, "p_lon": None}, False),
        # --- profile / photos -----------------------------------------
        ("profile/get_my_profile_completion", "get_my_profile_completion",
         {"p_user_id": uid}, False),
        ("profile/minimum_profile_photos", "minimum_profile_photos", {}, False),
        ("profile/maximum_profile_photos", "maximum_profile_photos", {}, False),
        ("profile/set_primary_profile_photo (nil photo -> expect guard)",
         "set_primary_profile_photo", {"p_photo_id": NIL}, False),
        ("profile/set_profile_photo_order", "set_profile_photo_order",
         {"p_photo_ids": []}, False),
        ("profile/get_user_interests", "get_user_interests", {"p_user_id": uid}, False),
        # --- notifications --------------------------------------------
        ("notifications/notification_unread_count", "notification_unread_count", {}, False),
        ("notifications/get_notifications", "get_notifications",
         {"p_limit": 5, "p_offset": 0}, False),
        ("notifications/mark_all_notifications_read", "mark_all_notifications_read", {}, False),
        # --- safety / moderation --------------------------------------
        ("safety/detect_social_media_in_text", "detect_social_media_in_text",
         {"p_text": "hello there"}, False),
        ("safety/submit_report (nil target -> expect guard)", "submit_report",
         {"p_reported_id": NIL, "p_report_type": "other", "p_description": "probe"}, True),
        # --- referrals / mfa ------------------------------------------
        ("referral/get_referral_stats", "get_referral_stats", {"p_user_id": uid}, False),
        ("referral/record_referral (nil inviter -> expect guard)", "record_referral",
         {"p_inviter_id": NIL, "p_referee_id": uid, "p_referral_code": "PROBE"}, True),
        ("auth/mfa_recovery_code_count", "mfa_recovery_code_count", {}, False),
        ("auth/consume_mfa_recovery_code", "consume_mfa_recovery_code", {"p_code": "000000"}, False),
        # --- crossed paths --------------------------------------------
        ("discovery/compute_crossed_paths", "compute_crossed_paths", {
            "p_user_id": uid, "p_geohash": "u4pruyd", "p_city": "Probe City",
            "p_locality": "Probe", "p_country": "IN"}, False),
    ]


def main() -> int:
    if not EMAIL or not PASSWORD:
        print("PROBE_EMAIL / PROBE_PASSWORD missing from .env.")
        print("Run: python tool/create_probe_account.py")
        return 2

    st, res = post("/auth/v1/token?grant_type=password", {"email": EMAIL, "password": PASSWORD})
    jwt = res.get("access_token") if isinstance(res, dict) else None
    if not jwt:
        print(f"could not authenticate probe account: HTTP {st}")
        print(json.dumps(res, indent=2)[:1200] if isinstance(res, dict) else str(res)[:1200])
        return 2
    uid = res["user"]["id"]
    print(f"authenticated probe account uid={uid}")
    print()

    results = []
    for label, fn, params, cross_user in probes(uid):
        status, body = rpc(fn, params, jwt)
        verdict = classify(status, body)
        results.append({
            "label": label, "rpc": fn, "http": status, "verdict": verdict,
            "cross_user_target": cross_user, "summary": summarize(body),
        })
        mark = {"LIVE": "ok   ", "GUARDED": "guard", "ABSENT": "MISS ", "DENIED": "deny ",
                "FAULT": "FAULT"}[verdict]
        print(f"  [{mark}] {label:58s} HTTP {status:3d}  {summarize(body)}")

    counts = {}
    for r in results:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print()
    print("totals: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    out = os.path.join(ROOT, "tool", "_auth_probe_results.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"probe_uid": uid, "counts": counts, "results": results}, fh, indent=2)
    print(f"wrote {out}")
    return 0 if counts.get("ABSENT", 0) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
