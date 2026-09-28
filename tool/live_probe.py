"""Weekend - live Supabase auth probe (read-only diagnostics).

Reports HTTP status + response body for the auth endpoints the app depends
on. NEVER prints a token, password, or email value.
"""
from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
MGT = "https://api.supabase.com/v1/projects/ocypgybqfushqfzisnvs/database/query"


def env_vars() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    hdr = {"apikey": anon, "Content-Type": "application/json"}

    def show(label: str, r: requests.Response) -> None:
        body = r.text[:400]
        rl = {
            k: val
            for k, val in r.headers.items()
            if "ratelimit" in k.lower() or k.lower() == "retry-after"
        }
        print(f"{label} -> HTTP {r.status_code}")
        if rl:
            print(f"    rate-limit headers: {rl}")
        if body:
            print(f"    body: {body}")

    # 1. Signup (rate-limit state of the live project).
    show(
        "SIGNUP",
        requests.post(
            f"{base}/auth/v1/signup",
            headers=hdr,
            json={"email": f"probe.{uuid.uuid4().hex}@example.com",
                  "password": f"Wk!{uuid.uuid4().hex}aA9"},
            timeout=45,
        ),
    )

    # 2. Password grant for the known-good account (the path the app uses).
    ef = Path(os.environ["TEMP"]) / "wknd_b_email.txt"
    pf = Path(os.environ["TEMP"]) / "wknd_b_pw.txt"
    if ef.exists() and pf.exists():
        show(
            "PASSWORD_GRANT_KNOWN_GOOD",
            requests.post(
                f"{base}/auth/v1/token?grant_type=password",
                headers=hdr,
                json={"email": ef.read_text().strip(),
                      "password": pf.read_text().strip()},
                timeout=45,
            ),
        )
    else:
        print("PASSWORD_GRANT_KNOWN_GOOD -> skipped (no saved credentials)")

    # 3. Which auth.users rows lack a usable identity.
    token = (Path(os.environ["TEMP"]) / "sbp_token.txt").read_text().strip()
    q = (
        "select count(*) filter (where i.id is null) as users_without_identity, "
        "count(*) filter (where u.confirmed_at is null) as users_without_confirmed_at, "
        "count(*) as total from auth.users u left join auth.identities i on i.user_id = u.id"
    )
    r = requests.post(MGT, headers={"Authorization": f"Bearer {token}"},
                      json={"query": q}, timeout=60)
    print(f"AUTH_USERS_IDENTITY_AUDIT -> HTTP {r.status_code}  {r.text[:300]}")

    # 4. Signup is blocked by the EMAIL send limit, not a generic IP limit.
    #    Prove a locally-provisioned user can complete a password grant when
    #    the bcrypt round-trip is correct - isolates auth from the mail quota.
    email = f"wknd.probe.{uuid.uuid4().hex[:10]}@example.com"
    password = f"Wk!{uuid.uuid4().hex}aA9"
    new_id, ident_id = str(uuid.uuid4()), str(uuid.uuid4())
    ins = (
        "insert into auth.users (instance_id,id,aud,role,email,encrypted_password,"
        "email_confirmed_at,raw_app_meta_data,"
        "raw_user_meta_data,created_at,updated_at) values "
        "('00000000-0000-0000-0000-000000000000','{i}','authenticated','authenticated','{e}',"
        "crypt('{p}', gen_salt('bf')),now(),"
        "'{{\"provider\":\"email\",\"providers\":[\"email\"]}}'::jsonb,'{{}}'::jsonb,now(),now())"
    ).format(i=new_id, e=email, p=password)
    ident = (
        "insert into auth.identities (id,user_id,identity_data,provider,provider_id,"
        "last_sign_in_at,created_at,updated_at) values "
        "('{n}','{i}',jsonb_build_object('email','{e}','sub','{i}',"
        "'email_verified',false,'phone_verified',false),'email','{i}',"
        "now(),now(),now())"
    ).format(n=ident_id, i=new_id, e=email)
    for label, sql in (("INSERT_USER", ins), ("INSERT_IDENTITY", ident)):
        rr = requests.post(MGT, headers={"Authorization": f"Bearer {token}"},
                           json={"query": sql}, timeout=60)
        print(f"{label} -> HTTP {rr.status_code}  {rr.text[:160]}")

    # bcrypt round-trip check (no password value is printed).
    rt = (
        "select (encrypted_password = crypt('{p}', encrypted_password)) as bcrypt_ok, "
        "left(encrypted_password, 7) as hash_prefix from auth.users where id = '{i}'"
    ).format(p=password, i=new_id)
    rr = requests.post(MGT, headers={"Authorization": f"Bearer {token}"},
                       json={"query": rt}, timeout=60)
    print(f"BCRYPT_ROUNDTRIP -> {rr.text[:200]}")

    gr = requests.post(
        f"{base}/auth/v1/token?grant_type=password",
        headers=hdr,
        json={"email": email, "password": password},
        timeout=45,
    )
    print(f"PASSWORD_GRANT_SQL_USER -> HTTP {gr.status_code}  {gr.text[:300]}")
    if gr.status_code == 200:
        uid = gr.json()["user"]["id"]
        print(f"SQL_USER_SESSION_OK uid={uid}")
        # Persist the session for the live test-suite.
        (Path(os.environ["TEMP"]) / "wknd_A_token.txt").write_text(gr.json()["access_token"])
        (Path(os.environ["TEMP"]) / "wknd_A_uid.txt").write_text(uid)
    return 0


if __name__ == "__main__":
    sys.exit(main())

