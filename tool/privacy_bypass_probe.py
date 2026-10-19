"""Empirically verify the search_profiles legacy-overload privacy bypass.

Two overloads of public.search_profiles are live at the same time:

  13-arg  (p_genders, ..., p_page, p_page_size)  <- the one the app's advanced
          search screen calls (lib/models/discovery_preferences.dart
          toRpcParams)
  21-arg  (p_limit, p_offset, ...)               <- the one the discovery feed
          calls (lib/models/discovery_models.dart/DTO toRpcParams)

031 hardened only the 21-argument version: it excludes candidates who are in
incognito mode, snooze mode, or who have switched online status off. The 13-arg
version predates 023/026/028/031 and contains none of those checks.

This script proves that with fixtures rather than by reading SQL:

  * builds two synthetic probe accounts, A (searcher) and B (the candidate)
  * gives both a discoverable profile at the same coordinates
  * B is visible to A through BOTH overloads
  * flip B into incognito mode
  * B disappears from the 21-arg result and REMAINS in the 13-arg result

Writes only to the two synthetic probe accounts and their own settings rows.
Run: python tool/privacy_bypass_probe.py
"""

from __future__ import annotations

import json
import os
import pathlib
import secrets
import string
import urllib.error
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
ROOT = pathlib.Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
TOKEN_FILE = pathlib.Path(os.environ.get("TEMP", ".")) / "sbp_token.txt"
NIL = "00000000-0000-0000-0000-000000000000"

B_EMAIL = "weekend.probe.candidate@example.com"
# Same coordinates for A and B so the distance filter can never be the reason a
# row is missing.
LAT, LON, CITY = 12.9716, 77.5946, "Probe City"
ALPHABET = string.ascii_letters + string.digits + "!@#%^*()-_=+"


def access_token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if t:
        return t
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def http(method, url, payload=None, headers=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
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


def load_env() -> dict:
    env = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k, v = s.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def append_env(pairs: dict) -> None:
    with ENV_FILE.open("a", encoding="utf-8") as fh:
        fh.write("\n# Second synthetic probe account (privacy-bypass verification).\n")
        for k, v in pairs.items():
            fh.write(f"{k}={v}\n")


def sql(query: str) -> list:
    status, body = http(
        "POST",
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        {"query": query},
        {"Authorization": f"Bearer {access_token()}", "Content-Type": "application/json"},
    )
    if status != 200 and status != 201:
        raise RuntimeError(f"sql failed HTTP {status}: {str(body)[:500]}")
    return body if isinstance(body, list) else []


def q1(query: str):
    rows = sql(query)
    return rows[0] if rows else {}


def service_role_key() -> str:
    _, body = http("GET", f"https://api.supabase.com/v1/projects/{PROJECT_REF}/api-keys?reveal=true",
                   headers={"Authorization": f"Bearer {access_token()}"})
    return next(k["api_key"] for k in body if k["name"] == "service_role")


def ensure_account(email: str, password: str | None) -> tuple[str, str]:
    """Create the account if missing; return (uid, password)."""
    svc = service_role_key()
    url = load_env()["SUPABASE_URL"].rstrip("/")
    admin = url + "/auth/v1/admin/users"
    hdr = {"Content-Type": "application/json", "Authorization": f"Bearer {svc}", "apikey": svc}
    _, body = http("GET", admin + "?page=1&per_page=200", headers=hdr)
    for u in body.get("users", []):
        if u.get("email") == email:
            if not password:
                raise SystemExit(f"{email} exists but no password recorded in .env")
            return u["id"], password
    password = password or "".join(secrets.choice(ALPHABET) for _ in range(28))
    status, body = http("POST", admin, {"email": email, "password": password, "email_confirm": True},
                        headers=hdr)
    if status not in (200, 201) or not body.get("id"):
        raise SystemExit(f"could not create {email}: HTTP {status} {str(body)[:300]}")
    return body["id"], password


def fixture_profile(uid: str, name: str, gender: str, dob: str) -> None:
    sql(f"""
    update public.profiles set
        display_name = '{name}',
        gender = '{gender}',
        date_of_birth = '{dob}',
        city = '{CITY}',
        locality = 'Probe',
        country = 'IN',
        latitude = {LAT},
        longitude = {LON},
        is_active = true,
        deleted_at = null,
        dating_profile_activated = true,
        profile_completion = 80,
        is_photo_verified = true,
        verification_status = 'verified',
        trust_score = 70,
        relationship_intent = 'Dating',
        last_active_at = now()
    where id = '{uid}'
    """)


def set_incognito(uid: str, on: bool) -> None:
    rows = sql(f"select 1 from public.user_settings where user_id = '{uid}'")
    if rows:
        sql(f"update public.user_settings set incognito_mode = {str(on).lower()} where user_id = '{uid}'")
    else:
        sql(f"insert into public.user_settings (user_id, incognito_mode) values ('{uid}', {str(on).lower()})")


def login(email: str, password: str) -> str:
    env = load_env()
    url = env["SUPABASE_URL"].rstrip("/")
    status, body = http("POST", url + "/auth/v1/token?grant_type=password",
                        {"email": email, "password": password},
                        {"apikey": env["SUPABASE_ANON_KEY"], "Content-Type": "application/json"})
    if not isinstance(body, dict) or "access_token" not in body:
        raise SystemExit(f"login failed for {email}: HTTP {status} {str(body)[:300]}")
    return body["access_token"]


def rpc(url: str, anon: str, jwt: str, fn: str, params: dict):
    return http("POST", f"{url}/rest/v1/rpc/{fn}", params,
                {"apikey": anon, "Authorization": f"Bearer {jwt}", "Content-Type": "application/json"})


def main() -> int:
    env = load_env()
    url = env["SUPABASE_URL"].rstrip("/")
    anon = env["SUPABASE_ANON_KEY"]

    a_email = env.get("PROBE_EMAIL")
    if not a_email or not env.get("PROBE_PASSWORD"):
        raise SystemExit("run tool/create_probe_account.py first (PROBE_EMAIL/PROBE_PASSWORD in .env)")

    a_uid, _ = ensure_account(a_email, env["PROBE_PASSWORD"])
    b_uid, b_pw = ensure_account(B_EMAIL, env.get("PROBE_B_PASSWORD"))
    if not env.get("PROBE_B_PASSWORD"):
        append_env({"PROBE_B_EMAIL": B_EMAIL, "PROBE_B_PASSWORD": b_pw})
        print("wrote PROBE_B_EMAIL / PROBE_B_PASSWORD to .env (gitignored)")
    print(f"A (searcher)  uid={a_uid}")
    print(f"B (candidate) uid={b_uid}")

    fixture_profile(a_uid, "Probe Alpha", "Man", "1994-03-03")
    fixture_profile(b_uid, "Probe Bravo", "Woman", "1995-05-05")

    a_jwt = login(env["PROBE_EMAIL"], env["PROBE_PASSWORD"])

    def search21():
        st, res = rpc(url, anon, a_jwt, "search_profiles", {
            "p_user_id": a_uid, "p_limit": 50, "p_offset": 0, "p_max_distance_km": 100,
            "p_search_lat": LAT, "p_search_lon": LON, "p_search_city": CITY,
            "p_genders": None, "p_age_min": 18, "p_age_max": 99, "p_interested_in": None,
            "p_relationship_intents": None, "p_cities": None, "p_interests": None,
            "p_languages": None, "p_smoking": None, "p_drinking": None, "p_exercise": None,
            "p_children": None, "p_pets": None, "p_include_dealt": False})
        return st, res

    def search13():
        st, res = rpc(url, anon, a_jwt, "search_profiles", {
            "p_user_id": a_uid, "p_genders": None, "p_age_min": 18, "p_age_max": 99,
            "p_max_distance_km": 100, "p_city": None, "p_relationship_intents": None,
            "p_interests": None, "p_languages": None, "p_lifestyle": None,
            "p_location_mode": "nearby", "p_page": 1, "p_page_size": 50})
        return st, res

    def presence(res):
        if not isinstance(res, list):
            return f"ERROR {str(res)[:80]}"
        ids = {r.get("profile_id") for r in res}
        return f"rows={len(res)} B_present={b_uid in ids}"

    print()
    print("=== control: B discoverable, incognito OFF ===")
    set_incognito(b_uid, False)
    print(f"   21-arg (discovery feed): {presence(search21()[1])}")
    print(f"   13-arg (search screen) : {presence(search13()[1])}")

    print()
    print("=== test: B is INCOGNITO ===")
    set_incognito(b_uid, True)
    st21, r21 = search21()
    st13, r13 = search13()
    print(f"   21-arg (discovery feed): {presence(r21)}   [expected: B absent]")
    print(f"   13-arg (search screen) : {presence(r13)}   [expected: B PRESENT = bypass]")
    leaked = isinstance(r13, list) and any(r.get("profile_id") == b_uid for r in r13)
    print()
    print("VERDICT:", "BYPASS CONFIRMED - incognito user still reachable via the 13-arg overload"
          if leaked else "no bypass observed")

    # leave the fixture in a neutral state
    set_incognito(b_uid, False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
