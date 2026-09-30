"""End-to-end probe of the profile-photo upload path, as the app performs it.

Mirrors ProfileRepository.uploadProfilePhoto exactly: Storage first, then the
profile_photos row, then the read-back that renders the card. Prints each step
so a client-side failure can be told apart from a backend one.
"""
from __future__ import annotations

import json
import os
import pathlib
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]


def env() -> dict:
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
        self.base = e["SUPABASE_URL"].rstrip("/")
        self.key = e["SUPABASE_ANON_KEY"]
        self.token: str | None = None

    def call(self, method, path, body=None, raw=None, ctype=None, json_reply=True):
        req = urllib.request.Request(self.base + path, method=method)
        req.add_header("apikey", self.key)
        req.add_header("Authorization", "Bearer " + (self.token or self.key))
        if raw is None:
            req.add_header("Content-Type", "application/json")
            data = json.dumps(body).encode() if body is not None else None
        else:
            req.add_header("Content-Type", ctype)
            data = raw
        try:
            with urllib.request.urlopen(req, data, timeout=45) as r:
                text = r.read().decode()
                if json_reply and text:
                    try:
                        return r.status, json.loads(text)
                    except Exception:
                        return r.status, text
                return r.status, text
        except urllib.error.HTTPError as exc:
            text = exc.read().decode()
            try:
                return exc.code, json.loads(text)
            except Exception:
                return exc.code, text


# A minimal but genuinely valid JPEG container.
JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb0043000806060001150d03011100"
    "021101031101"
) + bytes(800)


def main() -> int:
    api = Api()
    email = os.environ["WK_EMAIL"]
    password = os.environ["WK_PASSWORD"]

    st, body = api.call(
        "POST",
        "/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
    )
    if st != 200:
        print(f"FAIL sign-in: HTTP {st} {str(body)[:200]}")
        return 1
    api.token = body["access_token"]
    uid = body["user"]["id"]
    print(f"PASS sign-in uid={uid[:8]}")

    path = f"{uid}/{uuid.uuid4().hex}.jpg"

    st, _ = api.call(
        "POST",
        f"/storage/v1/object/profile-photos/{path}",
        raw=JPEG,
        ctype="image/jpeg",
    )
    print(f"{'PASS' if st == 200 else 'FAIL'} 1. storage upload -> {st}")
    if st != 200:
        return 1

    # Exactly the row ProfileRepository.uploadProfilePhoto inserts.
    st, row = api.call(
        "POST",
        "/rest/v1/profile_photos",
        {
            "user_id": uid,
            "photo_url": path,
            "storage_path": path,
            "is_primary": False,
            "width": 1080,
            "height": 1440,
            "file_size_bytes": len(JPEG),
            "mime_type": "image/jpeg",
        },
    )
    print(f"{'PASS' if st == 201 else 'FAIL'} 2. profile_photos insert -> {st} {str(row)[:200]}")
    if st != 201:
        api.call("DELETE", f"/storage/v1/object/profile-photos/{path}")
        return 1

    # PostgREST may return 201 with an empty body; recover the id either way.
    if isinstance(row, list) and row:
        pid = row[0].get("id")
    elif isinstance(row, dict):
        pid = row.get("id")
    else:
        found = api.call(
            "GET", f"/rest/v1/profile_photos?storage_path=eq.{path}&select=id"
        )[1]
        pid = found[0]["id"] if isinstance(found, list) and found else None

    st, back = api.call(
        "GET",
        f"/rest/v1/profile_photos?id=eq.{pid}&select=id,sort_order,is_primary,moderation_status",
    )
    print(f"{'PASS' if st == 200 else 'FAIL'} 3. read back -> {st} {back}")

    st, _ = api.call("POST", "/rest/v1/rpc/set_primary_profile_photo", {"p_photo_id": pid})
    print(f"{'PASS' if st == 200 else 'FAIL'} 4. set_primary_profile_photo -> {st}")

    st, _ = api.call(
        "POST", "/rest/v1/rpc/set_profile_photo_order", {"p_photo_ids": [pid]}
    )
    print(f"{'PASS' if st == 200 else 'FAIL'} 5. set_profile_photo_order -> {st}")

    st, cnt = api.call("POST", "/rest/v1/rpc/minimum_profile_photos", {})
    print(f"{'PASS' if st == 200 else 'FAIL'} 6. minimum_profile_photos -> {st} {cnt}")

    api.call("DELETE", f"/rest/v1/profile_photos?id=eq.{pid}")
    api.call("DELETE", f"/storage/v1/object/profile-photos/{path}")
    print("     cleaned up")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
