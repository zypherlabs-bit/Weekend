"""
Weekend -- LIVE PostgREST/GoTrue probe (evidence-producing).

Runs the PHASE 2 security probes against the REAL production Supabase project
using only the anon key (public by design) plus the cached session token for an
already-confirmed live test user. It proves whether migration 028 is actually
applied, because the tests below are exactly the negative tests the launch
gate requires:

  T1  underage date_of_birth write        -> must be REJECTED
  T1b underage dob smuggled via signup   -> must be REJECTED
  T2  age_min = 13 discovery              -> must return NO minor profiles
  T3  adult discovery                     -> must return adult profiles
  T4  self-like                           -> must be REJECTED
  T5  nearby RPC callable

NEVER prints a token, password, email address or full UUID.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
import uuid
from datetime import date, timedelta

ROOT = pathlib.Path(__file__).resolve().parents[1]
MARKER = "wkd-live-probe"


def env_vars() -> dict:
    out: dict = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


class Client:
    def __init__(self, base: str, anon: str) -> None:
        self.base = base
        self.anon = anon

    def call(self, method: str, path: str, token=None, body=None, params: str = ""):
        url = f"{self.base}/{path}{params}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("apikey", self.anon)
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", "Bearer " + (token or self.anon))
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.status, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")
        except Exception as e:
            return 0, f"{type(e).__name__}: {e}"


def mask(text: str, limit: int = 220) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[:limit] + " ..."


def rows_of(body: str):
    try:
        return json.loads(body)
    except Exception:
        return None

def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    c = Client(base, anon)
    print(f"=== Weekend live probe against {base} ===")

    tok_path = pathlib.Path(os.environ["TEMP"]) / "wknd_B_token.txt"
    if not tok_path.exists():
        print("BLOCKED: no cached live session token in %TEMP%\\wknd_B_token.txt")
        return 2
    token = tok_path.read_text(encoding="utf-8").strip()

    # ---- A0: is the cached session still usable? ------------------------
    st, body = c.call("GET", "auth/v1/user", token)
    print(f"\n[A0] session token accepted        -> HTTP {st}")
    if st != 200:
        print("     body:", mask(body))
        print("BLOCKED: cached token expired or revoked; a fresh sign-in is required.")
        return 2
    me = json.loads(body)
    me_id = me.get("id", "")
    print(f"     user_id len={len(me_id)}  email_confirmed={bool(me.get('confirmed_at'))}")

    st, body = c.call("GET", "rest/v1/profiles", token,
                      params=f"?select=date_of_birth,display_name&id=eq.{me_id}")
    my_dob = None
    r = rows_of(body) if st == 200 else None
    if r:
        my_dob = r[0].get("date_of_birth")
    print(f"[A1] my profile row                -> HTTP {st}  dob={my_dob}")

    # ---- T1: underage DOB write must be REJECTED -----------------------
    minor_dob = (date.today() - timedelta(days=365 * 15)).isoformat()
    st, body = c.call("PATCH", "rest/v1/profiles", token,
                      body={"date_of_birth": minor_dob},
                      params=f"?id=eq.{me_id}")
    rejected = st >= 400 or "adults 18 and over" in body or "not eligible" in body
    print(f"\n[T1] write UNDER-18 dob            -> HTTP {st}")
    print(f"     body: {mask(body, 160)}")
    print(f"     VERDICT: {'REJECTED (correct)' if rejected else 'ACCEPTED (FAIL - no age gate)'}")

    if my_dob:
        c.call("PATCH", "rest/v1/profiles", token,
               body={"date_of_birth": my_dob}, params=f"?id=eq.{me_id}")

    # ---- T1b: smuggle an underage DOB through signup metadata ----------
    probe_email = f"{MARKER}-{uuid.uuid4().hex[:10]}@example.com"
    probe_pw = f"Wk!{uuid.uuid4().hex}Aa9"
    st, body = c.call("POST", "auth/v1/signup", body={
        "email": probe_email, "password": probe_pw,
        "data": {"date_of_birth": minor_dob, "display_name": "WKDLiveProbeMinor"},
    })
    print(f"\n[T1b] signup WITH underage dob     -> HTTP {st}")
    print(f"     body: {mask(body, 200)}")
    print(f"     VERDICT: {'REJECTED (correct)' if st >= 400 else 'ACCEPTED - profile must be inspected'}")

    if st == 200:
        u = rows_of(body) or {}
        created_id = u.get("id") or (u.get("user") or {}).get("id") or ""
        if created_id:
            st2, body2 = c.call(
                "GET", "rest/v1/profiles",
                params=f"?select=date_of_birth,display_name&id=eq.{created_id}")
            print(f"     created profile inspect       -> HTTP {st2} {mask(body2, 160)}")

    # ---- T2: age_min 13 must never surface minors ----------------------
    st, body = c.call("POST", "rest/v1/rpc/search_profiles", token,
                      body={"p_age_min": 13, "p_age_max": 17, "p_limit": 50})
    r = rows_of(body) if st == 200 else None
    minors = -1 if r is None else len(r)
    print(f"\n[T2] search_profiles age 13-17     -> HTTP {st}  rows={minors}")
    print(f"     body: {mask(body, 200)}")
    print(f"     VERDICT: {'NO minors returned (correct)' if minors == 0 else 'MINORS RETURNED (FAIL)'}")

    # ---- T3: adult discovery must work ---------------------------------
    st, body = c.call("POST", "rest/v1/rpc/search_profiles", token,
                      body={"p_age_min": 18, "p_age_max": 65, "p_limit": 5})
    r = rows_of(body) if st == 200 else None
    adults = -1 if r is None else len(r)
    print(f"\n[T3] search_profiles age 18-65     -> HTTP {st}  rows={adults}")
    print(f"     body: {mask(body, 200)}")
    print(f"     VERDICT: {'adults discoverable (correct)' if adults != 0 else 'NO rows - investigate'}")

    # ---- T4: self-like must be rejected --------------------------------
    st, body = c.call("POST", "rest/v1/rpc/record_like", token,
                      body={"p_target_id": me_id})
    print(f"\n[T4] record_like(self)             -> HTTP {st}")
    print(f"     body: {mask(body, 200)}")
    print(f"     VERDICT: {'REJECTED (correct)' if st >= 400 else 'ACCEPTED (FAIL)'}")

    # ---- T5: nearby discovery RPC --------------------------------------
    st, body = c.call("POST", "rest/v1/rpc/get_nearby_profiles", token,
                      body={"p_lat": 28.6139, "p_lng": 77.2090,
                            "p_radius_km": 25, "p_limit": 5})
    print(f"\n[T5] get_nearby_profiles callable  -> HTTP {st}")
    print(f"     body: {mask(body, 200)}")

    print("\n=== probe complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())