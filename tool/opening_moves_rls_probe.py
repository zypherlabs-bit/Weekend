"""Empirically verify the Opening Moves save defect (and its fix) end to end.

Run: python tool/opening_moves_rls_probe.py

Context
-------
`public.opening_moves` (migration 032) is owner-row RLS:

    user_id uuid not null references public.profiles ...   -- no default
    unique (user_id, sort_order)
    policy opening_moves_insert_own for insert to authenticated
        with check (user_id = auth.uid())

The shipped client (lib/repositories/engagement_repository.dart,
OpeningMoveRepository.upsertAll) upserts this payload:

    { sort_order, prompt [, photo_id] }        <-- user_id is missing

Supabase-dart upsert() issues a PostgREST POST with
`Prefer: resolution=merge-duplicates` and `?on_conflict=user_id,sort_order`.
With no `user_id` in the body the row's user_id is NULL, so the insert policy's
WITH CHECK evaluates to NULL -> RLS rejects it and the Dart `catch` swallows the
error, leaving the editor showing "nothing happened".

This script drives the SAME REST calls the client makes, as the synthetic probe
account, and proves:

  A) the shipped payload is rejected            -> HTTP 403, code 42501
  B) the same payload + user_id is accepted     -> HTTP 201/200, row visible
  C) the row is readable back through RLS
  D) the probe then deletes it (leaves no fixture residue)

Only touches the synthetic probe account's own rows.
"""

from __future__ import annotations

import json
import os
import pathlib
import urllib.error
import urllib.request

PROJECT_REF = "ocypgybqfushqfzisnvs"
ROOT = pathlib.Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
TOKEN_FILE = pathlib.Path(os.environ.get("TEMP", ".")) / "sbp_token.txt"

SLOT = 1
PROMPT = "Coffee this weekend"


def access_token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    return t or TOKEN_FILE.read_text(encoding="utf-8").strip()


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


def sql(query: str) -> list:
    status, body = http(
        "POST",
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        {"query": query},
        {"Authorization": f"Bearer {access_token()}", "Content-Type": "application/json"},
    )
    if status not in (200, 201):
        raise RuntimeError(f"sql failed HTTP {status}: {str(body)[:500]}")
    return body if isinstance(body, list) else []


def main() -> int:
    env = load_env()
    url = env["SUPABASE_URL"].rstrip("/")
    anon = env["SUPABASE_ANON_KEY"]
    email = env["PROBE_EMAIL"]
    password = env["PROBE_PASSWORD"]

    status, auth = http(
        "POST",
        f"{url}/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
        {"apikey": anon, "Content-Type": "application/json"},
    )
    if status != 200:
        raise SystemExit(f"password grant failed HTTP {status}: {auth}")
    jwt = auth["access_token"]
    uid = auth["user"]["id"]
    print(f"authenticated as probe uid={uid}")

    # Start from a clean slate for the probe's own slot.
    sql(f"delete from public.opening_moves where user_id = '{uid}' and sort_order = {SLOT}")

    # Headers mirror supabase-dart's upsert(): merge-duplicates + on_conflict.
    http_upsert = {
        "apikey": anon,
        "Authorization": f"Bearer {jwt}",
        "Content-Type": "application/json",
        "Prefer": "return=representation,resolution=merge-duplicates",
    }
    endpoint = f"{url}/rest/v1/opening_moves?on_conflict=user_id,sort_order"

    print("\nA) shipped payload (NO user_id) — exactly what the app sends")
    st, body = http("POST", endpoint, {"sort_order": SLOT, "prompt": PROMPT}, http_upsert)
    print(f"   HTTP {st}  {json.dumps(body)[:200] if isinstance(body, (dict, list)) else body[:200]}")
    a_ok = st in (200, 201)

    print("\nB) fixed payload (+ user_id) — exactly the proposed change")
    st2, body2 = http(
        "POST", endpoint,
        {"user_id": uid, "sort_order": SLOT, "prompt": PROMPT},
        http_upsert,
    )
    print(f"   HTTP {st2}  {json.dumps(body2)[:300] if isinstance(body2, (dict, list)) else body2[:300]}")
    b_ok = st2 in (200, 201)

    print("\nC) read back through RLS (client fetchMine path)")
    st3, body3 = http(
        "GET",
        f"{url}/rest/v1/opening_moves?select=*&order=sort_order.asc",
        None,
        {"apikey": anon, "Authorization": f"Bearer {jwt}"},
    )
    print(f"   HTTP {st3}  {body3}")
    rows = body3 if isinstance(body3, list) else []
    c_ok = any(r.get("prompt") == PROMPT for r in rows)

    print("\nD) cleanup (delete the probe's own row through RLS)")
    st4, _ = http(
        "DELETE",
        f"{url}/rest/v1/opening_moves?user_id=eq.{uid}&sort_order=eq.{SLOT}",
        None,
        {"apikey": anon, "Authorization": f"Bearer {jwt}"},
    )
    print(f"   HTTP {st4}")
    residue = sql(f"select count(*) as n from public.opening_moves where user_id = '{uid}'")
    print(f"   rows left for probe: {residue}")

    print("\n--- verdict ---")
    print(f"  shipped payload rejected (expected 403/42501): {'PASS' if not a_ok else 'FAIL'}")
    print(f"  user_id payload accepted (expected 2xx):       {'PASS' if b_ok else 'FAIL'}")
    print(f"  row readable back through RLS:                 {'PASS' if c_ok else 'FAIL'}")
    ok = (not a_ok) and b_ok and c_ok
    print(f"  DEFECT CONFIRMED + FIX PROVEN: {'YES' if ok else 'NO'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
