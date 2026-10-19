"""Create (or reuse) the dedicated synthetic probe account on the LIVE project.

Uses the Management API admin endpoint with the project access token, because
self-service signup requires e-mail confirmation (mailer_autoconfirm=false) and
the probe has no mailbox. The account is created already confirmed.

The password is generated locally and written straight to the git-ignored .env
as PROBE_EMAIL / PROBE_PASSWORD. Nothing is printed except the e-mail and uid.

Usage: python tool/create_probe_account.py
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
EMAIL = "weekend.probe.agent@example.com"

ALPHABET = string.ascii_letters + string.digits + "!@#%^*()-_=+"


def token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if t:
        return t
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def call(method: str, url: str, payload=None, bearer=None, apikey=None) -> tuple[int, object]:
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"}
    headers["Authorization"] = "Bearer " + (bearer or token())
    if apikey:
        headers["apikey"] = apikey
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            return exc.code, json.loads(body)
        except json.JSONDecodeError:
            return exc.code, body


def service_role_key() -> str:
    status, body = call(
        "GET",
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/api-keys?reveal=true",
    )
    if status != 200 or not isinstance(body, list):
        raise SystemExit(f"cannot read api keys: HTTP {status}: {str(body)[:300]}")
    for k in body:
        if k.get("name") == "service_role":
            return k["api_key"]
    raise SystemExit("service_role key not found")


def load_config() -> tuple[str, str]:
    """Project URL + anon key from .env (already present)."""
    env = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k, v = s.split("=", 1)
            env[k.strip()] = v.strip()
    return env["SUPABASE_URL"].rstrip("/"), env["SUPABASE_ANON_KEY"]


def read_env() -> dict:
    out = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if s and not s.startswith("#") and "=" in s:
                k, v = s.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def main() -> int:
    env = read_env()
    email = env.get("PROBE_EMAIL", EMAIL)
    password = env.get("PROBE_PASSWORD", "")

    url, anon = load_config()
    svc = service_role_key()
    admin = url + "/auth/v1/admin/users"

    status, body = call("GET", admin + "?page=1&per_page=200", bearer=svc, apikey=svc)
    users = body.get("users", []) if isinstance(body, dict) else []
    existing = next((u for u in users if u.get("email") == email), None)

    if existing is None:
        if not password:
            password = "".join(secrets.choice(ALPHABET) for _ in range(28))
        status, body = call("POST", admin, {
            "email": email,
            "password": password,
            "email_confirm": True,
        }, bearer=svc, apikey=svc)
        if status not in (200, 201) or not isinstance(body, dict) or not body.get("id"):
            print(f"create failed: HTTP {status}: {str(body)[:400]}")
            return 1
        uid = body["id"]
        print(f"created probe account uid={uid} email={email} "
              f"confirmed={body.get('email_confirmed_at') is not None}")
    else:
        uid = existing.get("id")
        print(f"probe account exists uid={uid} email={email} "
              f"confirmed={existing.get('email_confirmed_at') is not None}")
        if not existing.get("email_confirmed_at"):
            st, _ = call("PUT", admin + f"/{uid}", {"email_confirm": True}, bearer=svc, apikey=svc)
            print(f"reconfirmed: HTTP {st}")
        if not password:
            print("no PROBE_PASSWORD in .env - set it manually to log in")
            return 2

    if not env.get("PROBE_EMAIL") or not env.get("PROBE_PASSWORD"):
        with ENV_FILE.open("a", encoding="utf-8") as fh:
            fh.write("\n# Synthetic live-probe account (created by tool/create_probe_account.py).\n")
            fh.write("# Git-ignored. Do not reuse for real user data.\n")
            fh.write(f"PROBE_EMAIL={email}\n")
            fh.write(f"PROBE_PASSWORD={password}\n")
        print("wrote PROBE_EMAIL / PROBE_PASSWORD to .env (gitignored)")
    else:
        print("PROBE_EMAIL / PROBE_PASSWORD already present in .env")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
