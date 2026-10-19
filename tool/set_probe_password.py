"""Rotate the synthetic probe account's password to a shell-safe value.

`adb shell input text` mangles punctuation, so for on-device sign-in the probe
password must be alphanumeric. Updates .env in place. Prints nothing secret.

Usage: python tool/set_probe_password.py
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
ALPHABET = string.ascii_letters + string.digits


def access_token() -> str:
    t = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if t:
        return t
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def call(method, url, payload=None, headers=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
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


def main() -> int:
    env = load_env()
    email = env.get("PROBE_EMAIL")
    if not email:
        raise SystemExit("PROBE_EMAIL missing; run tool/create_probe_account.py first")

    _, keys = call("GET", f"https://api.supabase.com/v1/projects/{PROJECT_REF}/api-keys?reveal=true",
                   headers={"Authorization": f"Bearer {access_token()}"})
    svc = next(k["api_key"] for k in keys if k["name"] == "service_role")
    url = env["SUPABASE_URL"].rstrip("/")
    hdr = {"Content-Type": "application/json", "Authorization": f"Bearer {svc}", "apikey": svc}

    _, body = call("GET", url + "/auth/v1/admin/users?page=1&per_page=200", headers=hdr)
    user = next((u for u in body.get("users", []) if u["email"] == email), None)
    if not user:
        raise SystemExit(f"{email} not found in the project")

    new_pw = "".join(secrets.choice(ALPHABET) for _ in range(24))
    status, _ = call("PUT", f"{url}/auth/v1/admin/users/{user['id']}",
                     {"password": new_pw, "email_confirm": True}, headers=hdr)
    if status not in (200, 201):
        raise SystemExit(f"password rotation failed: HTTP {status}")

    lines = ENV_FILE.read_text(encoding="utf-8").splitlines()
    out, replaced = [], False
    for line in lines:
        if line.startswith("PROBE_PASSWORD="):
            out.append(f"PROBE_PASSWORD={new_pw}")
            replaced = True
        else:
            out.append(line)
    if not replaced:
        out.append(f"PROBE_PASSWORD={new_pw}")
    ENV_FILE.write_text("\n".join(out) + "\n", encoding="utf-8")

    print(f"rotated password for {email} (uid={user['id']}, alphanumeric, {len(new_pw)} chars)")
    print("updated .env PROBE_PASSWORD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
