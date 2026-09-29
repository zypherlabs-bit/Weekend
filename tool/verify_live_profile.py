"""Live verification of the profile-experience backend (migration 025).

Exercises the RPCs the Edit Profile screen depends on, against the real project,
with a real user session. Prints PASS/FAIL per case and exits non-zero on any
failure so it can gate a release.

Run: python tool/verify_live_profile.py
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]


def env() -> dict[str, str]:
    out = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


class Api:
    def __init__(self) -> None:
        e = env()
        self.base = e["SUPABASE_URL"]
        self.key = e["SUPABASE_ANON_KEY"]
        self.token: str | None = None

    def call(self, method, path, body=None):
        req = urllib.request.Request(self.base + path, method=method)
        req.add_header("apikey", self.key)
        req.add_header(
            "Authorization", "Bearer " + (self.token or self.key)
        )
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urllib.request.urlopen(req, data, timeout=45) as r:
                return r.status, json.loads(r.read().decode() or "null")
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode()
            try:
                return exc.code, json.loads(raw)
            except Exception:
                return exc.code, raw


def main() -> int:
    api = Api()
    e = env()
    st, body = api.call(
        "POST",
        "/auth/v1/token?grant_type=password",
        {"email": os.environ["WK_EMAIL"], "password": os.environ["WK_PASSWORD"]},
    )
    if st != 200:
        print(f"FAIL  sign-in: HTTP {st} {str(body)[:200]}")
        return 1
    api.token = body["access_token"]
    uid = body["user"]["id"]
    print(f"PASS  sign-in (aal1 session) uid={uid[:8]}...")

    failures = 0

    st, mn = api.call("POST", "/rest/v1/rpc/minimum_profile_photos", {})
    ok = st == 200 and isinstance(mn, int) and mn >= 1
    print(f"{'PASS' if ok else 'FAIL'}  minimum_profile_photos -> {st} {mn}")
    failures += 0 if ok else 1

    st, mx = api.call("POST", "/rest/v1/rpc/maximum_profile_photos", {})
    ok = st == 200 and isinstance(mx, int) and mx >= mn
    print(f"{'PASS' if ok else 'FAIL'}  maximum_profile_photos -> {st} {mx}")
    failures += 0 if ok else 1

    # reorder RPC must reject an id the caller does not own.
    st, _ = api.call(
        "POST",
        "/rest/v1/rpc/set_profile_photo_order",
        {"p_photo_ids": ["00000000-0000-0000-0000-000000000000"]},
    )
    ok = st in (400, 403) or "do not belong" in json.dumps(_)
    print(f"{'PASS' if ok else 'FAIL'}  reorder rejects foreign photo id -> {st}")
    failures += 0 if ok else 1

    st, _ = api.call(
        "POST",
        "/rest/v1/rpc/set_primary_profile_photo",
        {"p_photo_id": "00000000-0000-0000-0000-000000000000"},
    )
    ok = st in (400, 403) or "do not belong" in json.dumps(_)
    print(f"{'PASS' if ok else 'FAIL'}  set_primary rejects foreign photo -> {st}")
    failures += 0 if ok else 1

    # interests taxonomy is seeded and readable.
    st, rows = api.call(
        "GET", "/rest/v1/interests?select=name,category&order=name"
    )
    names = {r["name"] for r in rows} if isinstance(rows, list) else set()
    wanted = {"Travel", "Movies", "Music festivals", "Photography", "Gaming"}
    ok = st == 200 and wanted.issubset(names)
    print(
        f"{'PASS' if ok else 'FAIL'}  interests taxonomy ({len(names)} rows) -> {st}"
    )
    failures += 0 if ok else 1

    # recovery codes: generate, spend once, refuse reuse.
    st, codes = api.call(
        "POST", "/rest/v1/rpc/generate_mfa_recovery_codes", {"p_count": 4}
    )
    ok = st == 200 and isinstance(codes, list) and len(codes) == 4
    print(f"{'PASS' if ok else 'FAIL'}  generate recovery codes -> {st}")
    failures += 0 if ok else 1
    if ok:
        code = codes[0]["code"]
        st, res = api.call(
            "POST", "/rest/v1/rpc/consume_mfa_recovery_code", {"p_code": code}
        )
        ok = st == 200 and res is True
        print(f"{'PASS' if ok else 'FAIL'}  consume valid code -> {res}")
        failures += 0 if ok else 1
        st, res = api.call(
            "POST", "/rest/v1/rpc/consume_mfa_recovery_code", {"p_code": code}
        )
        ok = st == 200 and res is False
        print(f"{'PASS' if ok else 'FAIL'}  reuse of spent code refused -> {res}")
        failures += 0 if ok else 1

    # The recovery-code table must not be writable from the client.
    st, _ = api.call(
        "POST",
        "/rest/v1/mfa_recovery_codes",
        {"user_id": uid, "code_hash": "a" * 64},
    )
    ok = st in (401, 403)
    print(f"{'PASS' if ok else 'FAIL'}  direct insert into recovery codes blocked -> {st}")
    failures += 0 if ok else 1

    print(f"\n{'ALL CHECKS PASSED' if failures == 0 else f'{failures} CHECK(S) FAILED'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
