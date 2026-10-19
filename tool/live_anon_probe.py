"""
Weekend -- LIVE anonymous probe.

Uses ONLY the public anon key (which ships inside the APK by design) to
establish, against the REAL production project:

  S1  GoTrue /auth/v1/settings   -> email confirmation, autoconfirm, signup
  S2  RPC catalogue               -> which stored procedures exist at all.
                                   PGRST202 = "function not found", which is
                                   how a missing migration shows up.
  S3  Storage buckets             -> the profile-photos bucket must be public
                                   or RLS-guarded, never world-writable.

Prints no secret values.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]


def env_vars() -> dict:
    out: dict = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def call(base: str, anon: str, path: str, method: str = "GET", body=None, params: str = ""):
    url = f"{base}/{path}{params}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", anon)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + anon)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, f"{type(e).__name__}: {e}"


def mask(t: str, n: int = 400) -> str:
    t = " ".join((t or "").split())
    return t if len(t) <= n else t[:n] + " ..."


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    print(f"=== Anonymous live probe against {base} ===\n")

    # ---- S1: GoTrue settings (public endpoint) --------------------------
    st, body = call(base, anon, "auth/v1/settings")
    print(f"[S1] GET /auth/v1/settings -> HTTP {st}")
    if st == 200:
        s = json.loads(body)
        keys = ("disable_signup", "mailer_autoconfirm", "external",
                "mailer_secure_email_change_enabled")
        for k in keys:
            print(f"     {k} = {s.get(k, '<absent>')}")
        mail = s.get("mailer_urlpaths", {}) or {}
        print(f"     mailer_urlpaths keys = {sorted(mail.keys())}")
        smtp = s.get("external", {}).get("smtp") or {}
        if smtp:
            print(f"     smtp host = {smtp.get('host')} user set = {bool(smtp.get('user'))}")
        else:
            print("     smtp = not reported (built-in Supabase mailer in use)")
        print(f"     mailer_autoconfirm = {s.get('mailer_autoconfirm')}"
              "   <- MUST be False: True means email verification is skipped")
    else:
        print("     body:", mask(body))

    # ---- S2: which RPCs exist? ------------------------------------------
    print("\n[S2] RPC catalogue (PGRST202 => function absent => migration NOT applied)")
    rpcs = [
        "search_profiles", "get_nearby_profiles", "record_like",
        "check_mutual_like", "delete_user_account", "get_ad_for_user",
        "record_ad_event", "compute_crossed_paths", "get_photo_urls",
        "assert_self", "handle_new_user", "enforce_adult_date_of_birth",
    ]
    for fn in rpcs:
        st, body = call(base, anon, f"rest/v1/rpc/{fn}", method="POST",
                        body={} if fn != "handle_new_user" else {"event": {}, "trigger": "x"})
        code = ""
        try:
            code = (json.loads(body) or {}).get("code", "")
        except Exception:
            code = ""
        exists = "ABSENT" if "PGRST202" in body else "present"
        print(f"     {fn:<32} HTTP {st:<4} {exists:<7} {code or mask(body, 90)}")

    # ---- S3: storage -----------------------------------------------------
    print("\n[S3] storage bucket visibility")
    st, body = call(base, anon, "storage/v1/bucket/profile-photos")
    print(f"     profile-photos bucket -> HTTP {st} {mask(body, 200)}")

    # ---- S4: a table must not be readable by anon -----------------------
    print("\n[S4] anon must NOT be able to read private tables")
    for t in ("profiles", "messages", "likes", "matches"):
        st, body = call(base, anon, f"rest/v1/{t}", params="?select=*&limit=1")
        leaks = st == 200 and body.strip() not in ("[]", "")
        print(f"     {t:<12} HTTP {st:<4} {'LEAK' if leaks else 'blocked (correct)'}"
              f"  {mask(body, 80) if leaks else ''}")

    print("\n=== probe complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())