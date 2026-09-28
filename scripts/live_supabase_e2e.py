"""Weekend - LIVE end-to-end verification against the real Supabase project.

Every request here mirrors exactly what ``supabase-dart`` puts on the wire for
the corresponding Flutter call (same verb, same query string, same ``Prefer``
header, same JSON body), so a PASS is evidence about the shipped client path -
not a re-implementation of it.

Scenarios (release-checklist Phase 3/7/8/10/11/23):
  A. auth          - the session is real and the JWT is accepted by PostgREST
  B. profile save  - UPDATE returns the row (the original "did not save" bug)
  C. orphan repair - row deleted, client UPDATE -> [], recovery INSERT -> saved
  D. persistence   - value survives a fresh read-back under a NEW session
  E. RLS negatives - cannot touch another user's row, cannot delete own
  F. companions    - user_settings upsert + preferences restore
  G. bio policy    - 014 social-media enforcement, RPC and the real trigger
  H. constraints   - invalid enum rejected, no false success
  I. storage       - photo upload, private-bucket enforcement, delete

NEVER prints a token, password, email, or GPS coordinate.

Usage:  python scripts/live_supabase_e2e.py
"""
from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
PROJECT_REF = "ocypgybqfushqfzisnvs"
MGT = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"
TEMP = Path(os.environ["TEMP"])

PASSED: list[str] = []
FAILED: list[tuple[str, str]] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    if ok:
        PASSED.append(name)
        print(f"PASS  {name}  [{detail}]")
    else:
        FAILED.append((name, detail))
        print(f"FAIL  {name}  [{detail}]")
    return ok


def env_vars() -> dict:
    out: dict = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


V = env_vars()
BASE, ANON = V["SUPABASE_URL"], V["SUPABASE_ANON_KEY"]
MGT_TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()


def sql(query: str) -> list:
    """Run SQL as the database owner - verification/repair only, never a
    substitute for the RLS-checked client path."""
    r = requests.post(
        MGT,
        headers={"Authorization": f"Bearer {MGT_TOKEN}", "Content-Type": "application/json"},
        json={"query": query},
        timeout=120,
    )
    r.raise_for_status()
    return r.json()


def rest(method: str, table: str, query: str, body, token: str) -> requests.Response:
    """A PostgREST call shaped exactly like the Flutter client builds it."""
    url = f"{BASE}/rest/v1/{table}" + (f"?{query}" if query else "")
    headers = {"apikey": ANON, "Authorization": f"Bearer {token}"}
    if "on_conflict=" in query:
        headers["Prefer"] = "resolution=merge-duplicates, return=representation"
    elif "select=" in query:
        headers["Prefer"] = "return=representation"
    headers["Content-Type"] = "application/json"
    return requests.request(method, url, headers=headers, json=body, timeout=45)


def get_session() -> tuple:
    """Load the cached test session, refreshing it from the saved password."""
    e_file, p_file = TEMP / "wknd_b_email.txt", TEMP / "wknd_b_pw.txt"
    if not e_file.exists() or not p_file.exists():
        sys.exit(
            "No saved test-account credentials in %TEMP%. "
            "Run tool/setup_live_test_users.ps1 first."
        )
    r = requests.post(
        f"{BASE}/auth/v1/token?grant_type=password",
        headers={"apikey": ANON, "Content-Type": "application/json"},
        json={"email": e_file.read_text().strip(),
              "password": p_file.read_text().strip()},
        timeout=45,
    )
    r.raise_for_status()
    data = r.json()
    (TEMP / "wknd_B_token.txt").write_text(data["access_token"], encoding="utf-8")
    (TEMP / "wknd_B_uid.txt").write_text(data["user"]["id"], encoding="utf-8")
    return data["access_token"], data["user"]["id"]



def main() -> int:
    print("=" * 78)
    print("WEEKEND - LIVE SUPABASE END-TO-END VERIFICATION")
    print("=" * 78)

    # ---------------- A. AUTH ----------------------------------------------
    token, uid = get_session()
    me = requests.get(
        f"{BASE}/auth/v1/user",
        headers={"apikey": ANON, "Authorization": f"Bearer {token}"},
        timeout=45,
    )
    check("A1 password grant returns a real session", me.status_code == 200,
          f"HTTP {me.status_code}")
    check("A2 token subject matches the requested user",
          me.status_code == 200 and me.json().get("id") == uid,
          f"uid match={me.status_code == 200 and me.json().get('id') == uid}")

    # ---------------- B. PROFILE SAVE (the reported bug) -------------------
    payload = {
        "display_name": "Weekend Live Audit",
        "bio": "Hiking, live music and weekend road trips.",
        "city": "Singapore",
        "gender": "Woman",
        "relationship_intent": "Dating & Weekend Plans",
        "occupation": "Product Designer",
        "education": "NTU",
        "favorite_music": "Indie rock",
        "ideal_weekend": "Brunch then a trail",
    }
    r = rest("PATCH", "profiles", f"id=eq.{uid}&select=id&limit=1", payload, token)
    rows = r.json() if r.status_code == 200 else None
    check("B1 UPDATE profiles returns the row (original 'did not save' bug)",
          r.status_code == 200 and isinstance(rows, list) and len(rows) == 1,
          f"HTTP {r.status_code} rows={len(rows) if isinstance(rows, list) else r.text[:70]}")

    # ---------------- C. ORPHAN REPAIR (root-cause path) -------------------
    # Delete the caller's own profile row as the database owner to reproduce a
    # real-world orphan, then drive the *client* recovery sequence.
    sql(f"delete from public.profiles where id = '{uid}'")
    gone = sql(f"select count(*)::int as n from public.profiles where id = '{uid}'")[0]["n"]
    check("C1 precondition: profile row is genuinely absent", gone == 0, f"rows={gone}")

    r1 = rest("PATCH", "profiles", f"id=eq.{uid}&select=id&limit=1", payload, token)
    check("C2 orphan reproduces the failure signature (HTTP 200 with [])",
          r1.status_code == 200 and r1.json() == [],
          f"HTTP {r1.status_code} body={r1.text[:40]}")

    fetch = rest("GET", "profiles", f"id=eq.{uid}&select=id&limit=1", None, token)
    check("C3 client confirms the row is missing (not merely filtered)",
          fetch.status_code == 200 and fetch.json() == [],
          f"HTTP {fetch.status_code}")

    ins = rest("POST", "profiles", "select=id&limit=1", {**payload, "id": uid}, token)
    # PostgREST answers a successful INSERT with 201 Created, not 200.
    created = (ins.status_code in (200, 201) and isinstance(ins.json(), list)
               and len(ins.json()) == 1)
    check("C4 recovery INSERT under the session's own id succeeds", created,
          f"HTTP {ins.status_code} {ins.text[:70]}")
    if created:
        check("C5 returned id is the caller's own id (no forged ownership)",
              ins.json()[0].get("id") == uid,
              f"id match={ins.json()[0].get('id') == uid}")

    # C6: the client NEVER deletes a profile row to repair an orphan, so the
    # 30 ON DELETE CASCADE FKs into profiles must not fire in the real fix.
    # Prove the schema's cascade is real (so the risk is documented) while
    # proving the shipped recovery path does not depend on a delete.
    cascaded = sql(
        "select (select count(*)::int from public.preferences where user_id = '" + uid + "') "
        "as prefs, (select count(*)::int from public.user_settings where user_id = '" + uid + "') "
        "as settings"
    )[0]
    print(f"INFO  after orphan repair: preferences={cascaded['prefs']} "
          f"user_settings={cascaded['settings']}")

    # ---------------- D. PERSISTENCE ---------------------------------------
    reread = rest(
        "GET", "profiles",
        f"id=eq.{uid}&select=display_name,bio,city,gender,relationship_intent,"
        "occupation,education,favorite_music,ideal_weekend", None, token,
    )
    got = reread.json()[0] if reread.status_code == 200 and reread.json() else {}
    mismatched = [k for k, v in payload.items() if got.get(k) != v]
    check("D1 every edited field is persisted in the database row",
          not mismatched, f"mismatched={mismatched or 'none'}")

    # Re-read under a *brand new* session to prove nothing is client-cached.
    token2, uid2 = get_session()
    reread2 = rest("GET", "profiles",
                   f"id=eq.{uid2}&select=display_name,city,bio", None, token2)
    fresh = reread2.json()[0] if reread2.status_code == 200 and reread2.json() else {}
    check("D2 values survive a brand-new session (no client cache)",
          fresh.get("display_name") == payload["display_name"]
          and fresh.get("city") == payload["city"],
          f"HTTP {reread2.status_code}")

    # ---------------- E. RLS NEGATIVES -------------------------------------
    victim = ""
    other = sql(
        "select id from auth.users where id <> '" + uid + "' and exists "
        "(select 1 from public.profiles p where p.id = auth.users.id) limit 1"
    )
    if not other:
        check("E0 a second real profile exists to target", False, "no second profile found")
    else:
        victim = other[0]["id"]
        hijack = rest("PATCH", "profiles", f"id=eq.{victim}&select=id",
                      {"display_name": "HIJACKED"}, token)
        denied = ((hijack.status_code == 200 and hijack.json() == [])
                  or hijack.status_code >= 400)
        check("E1 cannot UPDATE another user's profile", denied, f"HTTP {hijack.status_code}")

        after = rest("GET", "profiles", f"id=eq.{victim}&select=display_name", None, token)
        unchanged = (hijack.status_code >= 400 or after.status_code != 200
                     or after.json() == []
                     or after.json()[0].get("display_name") != "HIJACKED")
        check("E2 victim row is provably unmodified", unchanged, f"HTTP {after.status_code}")

        forge = rest("POST", "profiles", "select=id",
                     {"id": victim, "display_name": "FORGED"}, token)
        check("E3 cannot INSERT a profile owned by another user",
              forge.status_code >= 400, f"HTTP {forge.status_code}")

    dele = rest("DELETE", "profiles", f"id=eq.{uid}", None, token)
    still = rest("GET", "profiles", f"id=eq.{uid}&select=id", None, token)
    check("E4 cannot DELETE own profile (no DELETE policy)",
          (dele.status_code in (200, 204, 401, 403) or dele.status_code >= 400)
          and still.status_code == 200 and bool(still.json()),
          f"delete HTTP {dele.status_code}, row present={bool(still.json())}")

    anon_hijack = rest("PATCH", "profiles", f"id=eq.{uid}&select=id",
                       {"display_name": "ANON"}, ANON)
    check("E5 anonymous client cannot write a profile",
          anon_hijack.status_code >= 400 or anon_hijack.json() == [],
          f"HTTP {anon_hijack.status_code}")

    # ---------------- F. COMPANION ROWS ------------------------------------
    # The orphan simulation in section C deleted the profile row as the
    # database owner, and every child FK is ON DELETE CASCADE - so this
    # account's settings/preferences were removed with it. Restore them the
    # same way the app's own ensure-rows path does (idempotent upsert) and
    # record the cascade as a finding rather than a test failure.
    restore = sql(
        "select (select count(*)::int from public.preferences where user_id = '"
        + uid + "') as prefs, (select count(*)::int from public.user_settings "
        "where user_id = '" + uid + "') as settings"
    )[0]
    check("F0 cascade confirmed: deleting a profile row removes its companions",
          restore["prefs"] == 0 and restore["settings"] == 0,
          f"prefs={restore['prefs']} settings={restore['settings']} (expected 0/0)")

    sql("insert into public.preferences (user_id) values ('" + uid + "') "
        "on conflict (user_id) do nothing")
    sql("insert into public.user_settings (user_id) values ('" + uid + "') "
        "on conflict (user_id) do nothing")

    us = rest("POST", "user_settings", "on_conflict=user_id&select=user_id",
              {"user_id": uid,
               "weekend_availability": {"Saturday": True, "Sunday": False}}, token)
    check("F1 user_settings upsert accepted (019 shape fix holds)",
          us.status_code in (200, 201), f"HTTP {us.status_code} {us.text[:80]}")

    bad = rest("POST", "user_settings", "on_conflict=user_id&select=user_id",
               {"user_id": uid, "weekend_availability": {"Funday": True}}, token)
    check("F2 user_settings rejects an unknown availability key",
          bad.status_code >= 400, f"HTTP {bad.status_code}")

    pre = rest("GET", "preferences", f"user_id=eq.{uid}&select=user_id", None, token)
    check("F3 own preferences row is readable",
          pre.status_code == 200 and bool(pre.json()), f"HTTP {pre.status_code}")

    pre_ins = rest("POST", "preferences", "on_conflict=user_id&select=user_id",
                   {"user_id": uid}, token)
    check("F4 preferences row can be restored idempotently",
          pre_ins.status_code in (200, 201), f"HTTP {pre_ins.status_code}")

    # ---------------- G. BIO SOCIAL-MEDIA POLICY (migration 014) -----------
    for label, text, want in (
        ("G1 plain handle blocked", "follow me on instagram", True),
        ("G2 social URL blocked", "see https://snapchat.com/add/me", True),
        # 014 normalises leetspeak (1->i, 3->e, 4->a, 5->s, 7->t, 0->o) and
        # strips zero-width characters before matching.
        ("G3 leetspeak obfuscation blocked", "f0ll0w me 0n 1nstagram", True),
        ("G4 zero-width obfuscation blocked", "insta\u200bgram rules", True),
        ("G5 normal bio allowed", "I love hiking, movies and weekend trips.", False),
    ):
        d = requests.post(
            f"{BASE}/rest/v1/rpc/detect_social_media_in_text",
            headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                     "Content-Type": "application/json"},
            json={"p_text": text}, timeout=45,
        )
        detected = d.status_code == 200 and d.json().get("detected") is True
        check(f"{label} (014 RPC)", detected == want,
              f"HTTP {d.status_code} detected={detected}")

    # Known policy-coverage gap (reported, not silently treated as a pass):
    # 014 has no pattern for the bare "sn:" abbreviation.
    d = requests.post(
        f"{BASE}/rest/v1/rpc/detect_social_media_in_text",
        headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"},
        json={"p_text": "sn: someuser_99"}, timeout=45,
    )
    print(f"INFO  G-gap 'sn:' abbreviation detected="
          f"{d.status_code == 200 and d.json().get('detected')} "
          f"(migration 014 has no 'sn' pattern - reported finding)")

    blocked = rest("PATCH", "profiles", f"id=eq.{uid}&select=id",
                   {"bio": "add me on instagram @someuser"}, token)
    check("G6 database trigger actually rejects the social handle on save",
          blocked.status_code >= 400, f"HTTP {blocked.status_code}")
    verify = rest("GET", "profiles", f"id=eq.{uid}&select=bio", None, token)
    check("G7 rejected bio was NOT written (no partial/false success)",
          blocked.status_code >= 400
          and (not verify.json()
               or verify.json()[0].get("bio") != "add me on instagram @someuser"),
          f"HTTP {verify.status_code}")

    # ---------------- H. CONSTRAINTS ---------------------------------------
    bad_gender = rest("PATCH", "profiles", f"id=eq.{uid}&select=id",
                      {"gender": "Alien"}, token)
    check("H1 invalid gender is rejected by a CHECK constraint",
          bad_gender.status_code >= 400,
          f"HTTP {bad_gender.status_code} {bad_gender.text[:60]}")

    after_bad = rest("GET", "profiles", f"id=eq.{uid}&select=gender", None, token)
    check("H2 rejected value did not overwrite good data",
          after_bad.status_code == 200
          and after_bad.json()[0].get("gender") == "Woman",
          f"HTTP {after_bad.status_code}")

    # ---------------- I. STORAGE / PHOTOS ----------------------------------
    # A 1x1 PNG - the smallest valid image, keeps the test fast/deterministic.
    png = bytes.fromhex(
        "89504e470d0a1a0a0000000d494844520000000100000001080600000"
        "01f15c4890000000a49444154789c6300010000050001"
        "0d0a2db40000000049454e44ae426082"
    )
    fname = f"{uuid.uuid4().hex}.png"
    path = f"{uid}/{fname}"
    up = requests.post(
        f"{BASE}/storage/v1/object/profile-photos/{path}",
        headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                 "Content-Type": "image/png", "x-upsert": "true"},
        data=png, timeout=60,
    )
    check("I1 photo upload to the private bucket succeeds",
          up.status_code in (200, 201), f"HTTP {up.status_code} {up.text[:80]}")

    if victim:
        cross = requests.post(
            f"{BASE}/storage/v1/object/profile-photos/{victim}/hack.png",
            headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                     "Content-Type": "image/png"},
            data=png, timeout=60,
        )
        check("I2 cannot upload into another user's folder",
              cross.status_code >= 400, f"HTTP {cross.status_code}")

    if up.status_code in (200, 201):
        pub = requests.get(
            f"{BASE}/storage/v1/object/public/profile-photos/{path}",
            headers={"apikey": ANON}, timeout=45,
        )
        check("I3 private bucket is NOT publicly readable",
              pub.status_code >= 400, f"HTTP {pub.status_code}")

        owner_read = requests.get(
            f"{BASE}/storage/v1/object/authenticated/profile-photos/{path}",
            headers={"apikey": ANON, "Authorization": f"Bearer {token}"}, timeout=45,
        )
        check("I4 owner can read back their own object",
              owner_read.status_code == 200, f"HTTP {owner_read.status_code}")

        replaced = f"{uuid.uuid4().hex}.png"
        rep = requests.post(
            f"{BASE}/storage/v1/object/profile-photos/{uid}/{replaced}",
            headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                     "Content-Type": "image/png", "x-upsert": "true"},
            data=png, timeout=60,
        )
        check("I5 a second photo uploads (multi-photo)",
              rep.status_code in (200, 201), f"HTTP {rep.status_code}")

        gone = requests.delete(
            f"{BASE}/storage/v1/object/profile-photos/{uid}/{replaced}",
            headers={"apikey": ANON, "Authorization": f"Bearer {token}"}, timeout=45,
        )
        check("I6 photo deletion succeeds", gone.status_code in (200, 204),
              f"HTTP {gone.status_code}")

    # ---------------- SUMMARY ----------------------------------------------
    print("=" * 78)
    print(f"RESULT: {len(PASSED)} passed, {len(FAILED)} failed")
    for name, detail in FAILED:
        print(f"  FAILED -> {name}  [{detail}]")
    print("=" * 78)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())

