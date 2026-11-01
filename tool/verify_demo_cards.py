"""Verify the 5 seeded demo profiles return through the real discovery RPC.

Signs in as the probe account (the RPC asserts p_user_id = auth.uid()), then
calls get_nearby_profiles exactly as DiscoveryRepository does. This is the
gate before taking screenshots: if it returns 5 rows with photo paths, the
discovery feed will render cards.

Development-only. Prints names/distances only - never tokens.
"""
import json
import pathlib
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
env = {}
for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
    s = line.strip()
    if s and not s.startswith("#") and "=" in s:
        k, v = s.split("=", 1)
        env[k.strip()] = v.strip()

BASE = env["SUPABASE_URL"].rstrip("/")
ANON = env["SUPABASE_ANON_KEY"]


def call(path, payload=None, token=None, method=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, method=method or ("POST" if data else "GET"))
    req.add_header("apikey", ANON)
    req.add_header("Authorization", "Bearer " + (token or ANON))
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        # The body must be handed to urlopen(), not just built above - otherwise
        # the server receives an empty request and replies "bad_json".
        with urllib.request.urlopen(req, data, timeout=60) as r:
            text = r.read().decode()
            return r.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(text)
        except json.JSONDecodeError:
            return e.code, text


st, body = call("/auth/v1/token?grant_type=password",
                {"email": env["PROBE_EMAIL"], "password": env["PROBE_PASSWORD"]})
if st != 200:
    print(f"FAIL probe sign-in: HTTP {st} {str(body)[:200]}")
    raise SystemExit(1)
tok = body["access_token"]
uid = body["user"]["id"]
print(f"probe signed in uid={uid[:8]}")

# Exactly the parameter set DiscoveryRepository.loadDiscoveryProfiles sends.
st, rows = call("/rest/v1/rpc/get_nearby_profiles", {
    "p_user_id": uid,
    "p_limit": 20,
    "p_offset": 0,
    "p_max_distance_km": 50.0,
    "p_preferred_genders": [],
    "p_age_min": 18,
    "p_age_max": 65,
    "p_discovery_mode": "nearby",
    "p_last_active_hours": None,
}, token=tok)

if st != 200:
    print(f"FAIL rpc: HTTP {st} {str(rows)[:300]}")
    raise SystemExit(1)

print(f"\nRPC returned {len(rows)} row(s):\n")
for r in rows:
    photo = "YES" if r.get("primary_photo_path") else "NO PHOTO"
    interests = r.get("interests") or []
    print(f"  {r.get('display_name','?'):<10} age={r.get('age')} "
          f"dist={r.get('distance_km')}km city={r.get('city')} "
          f"photo={photo} interests={len(interests)}")

has_photo = sum(1 for r in rows if r.get("primary_photo_path"))
print(f"\nrows={len(rows)}  with_photo={has_photo}")
print("PASS" if len(rows) >= 5 and has_photo >= 5 else "CHECK NEEDED")
