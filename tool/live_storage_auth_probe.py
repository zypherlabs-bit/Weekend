"""
Weekend -- LIVE Storage + Auth endpoint verification.

Storage: profile photo upload is a Play-blocking feature and a core promise of
the product, so the bucket must actually exist in production. The Supabase
Storage API answers NoSuchBucket straight from S3 when it does not.

Auth: verifies the email-confirmation configuration that Phase 3 depends on,
and probes the password-recovery endpoint without ever sending a real mail.

Uses only the public anon key. Never prints a token, password or email.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

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


def call(base, anon, path, method="GET", body=None, params=""):
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
    except Exception as e:  # noqa: BLE001
        return 0, f"{type(e).__name__}: {e}"


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    print(f"=== Storage + Auth verification: {base} ===\n")

    print("[STORAGE]")
    st, body = call(base, anon, "storage/v1/bucket/profile-photos")
    print(f"  GET bucket/profile-photos -> HTTP {st}")
    print(f"    {body[:220]}")
    verdict = "MISSING" if "NoSuchBucket" in body or "not found" in body.lower() else "present"
    print(f"    verdict: {verdict}")

    # Upload without a real object: if the bucket is missing this 404s first,
    # if it exists this fails on the key/object instead. Distinguishes the two.
    st2, body2 = call(base, anon, "storage/v1/object/profile-photos/probe.txt",
                      method="POST", body=b"")
    print(f"  POST object (probe)         -> HTTP {st2}")
    print(f"    {body2[:220]}")

    print("\n[AUTH]")
    st, body = call(base, anon, "auth/v1/settings")
    s = json.loads(body) if st == 200 else {}
    print(f"  /auth/v1/settings -> HTTP {st}")
    print(f"    disable_signup      = {s.get('disable_signup')}")
    print(f"    mailer_autoconfirm  = {s.get('mailer_autoconfirm')}"
          f"   ({'CONFIRMATION REQUIRED (correct)' if s.get('mailer_autoconfirm') is False else 'CHECK'})")
    print(f"    password_min_length = {s.get('password_min_length')}")

    # Password recovery: a real request to a non-existent mailbox must return
    # 200 (no user enumeration) or 404. It proves the endpoint is wired.
    st, body = call(base, anon, "auth/v1/recover", method="POST",
                    body={"email": f"nonexistent-{uuid.uuid4().hex[:8]}@example.invalid"})
    print(f"  POST /auth/v1/recover -> HTTP {st}")
    print(f"    {body[:200]}")

    # Invalid-credential probe: must be 400 with an auth error, never 500.
    st, body = call(base, anon, "auth/v1/token?grant_type=password", method="POST",
                    body={"email": f"nonexistent-{uuid.uuid4().hex[:8]}@example.invalid",
                          "password": "definitely-not-the-password"})
    print(f"  POST token (bad creds)  -> HTTP {st}")
    print(f"    {body[:200]}")

    print("\n=== verification complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())