"""Probe the live backend as an AUTHENTICATED synthetic account.

Anon-key probes cannot distinguish "function absent" from "function exists but
EXECUTE revoked from anon". This script signs up/logs in a dedicated synthetic
probe account, then calls each marker RPC with the user's JWT.

Reads SUPABASE_URL / SUPABASE_ANON_KEY from .env. Writes nothing to user data
tables except the probe auth account itself.
"""
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_env():
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

# Probe test account. Credentials come from .env (PROBE_EMAIL / PROBE_PASSWORD)
# so nothing account-specific is committed to version control.
EMAIL = ENV.get("PROBE_EMAIL", "")
PASSWORD = ENV.get("PROBE_PASSWORD", "")


def post(path, payload, jwt=None):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("apikey", ANON)
    if jwt:
        req.add_header("Authorization", "Bearer " + jwt)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except json.JSONDecodeError:
            return e.code, body


def rpc(name, params, jwt):
    return post("/rest/v1/rpc/" + name, params or {}, jwt)


def main():
    # 1. Try signup; if account already exists, fall back to login.
    st, res = post("/auth/v1/signup", {"email": EMAIL, "password": PASSWORD})
    if st in (400, 422) and isinstance(res, dict):
        print(f"signup -> {st} ({res.get('error_description') or res.get('msg') or 'exists/invalid'}); trying login")
        st, res = post("/auth/v1/token?grant_type=password", {"email": EMAIL, "password": PASSWORD})
    jwt = res.get("access_token") if isinstance(res, dict) else None
    if not jwt:
        print(f"Could not authenticate probe account: HTTP {st}")
        print(json.dumps(res, indent=2)[:2000] if isinstance(res, dict) else str(res)[:2000])
        sys.exit(2)
    uid = res.get("user", {}).get("id")
    print(f"authenticated as probe account {uid}")

    # 2. Probe marker RPCs with the EXACT parameter names from migrations.
    probes = {
        "026 base get_received_likes": ("get_received_likes", {"p_limit": 1, "p_offset": 0}),
        "026 base get_matches_for_user": ("get_matches_for_user", {}),
        "026/028 record_like": ("record_like", {"p_target_id": "00000000-0000-0000-0000-000000000000", "p_is_stand_out": False}),
        "023 search_profiles": (
            "search_profiles",
            {
                "p_limit": 1,
                "p_offset": 0,
                "p_genders": None,
                "p_interested_in": None,
                "p_age_min": None,
                "p_age_max": None,
                "p_cities": None,
                "p_max_distance_km": None,
                "p_intents": None,
                "p_interests": None,
                "p_languages": None,
                "p_smoking": None,
                "p_drinking": None,
                "p_exercise": None,
                "p_children": None,
                "p_pets": None,
                "p_include_dealt": False,
                "p_search_lat": None,
                "p_search_lon": None,
            },
        ),
    }

    results = {}
    for label, (fn, params) in probes.items():
        st, res = rpc(fn, params, jwt)
        verdict = "ABSENT" if (st == 404 or (isinstance(res, dict) and res.get("code") == "PGRST202")) else f"EXISTS (HTTP {st})"
        results[label] = {"http": st, "verdict": verdict, "body": res if not isinstance(res, dict) else json.dumps(res)[:600]}
        print(f"  [{label}] HTTP {st}  {verdict}")

    with open(os.path.join(ROOT, "tool", "_auth_probe_results.json"), "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2, default=str)


if __name__ == "__main__":
    main()
