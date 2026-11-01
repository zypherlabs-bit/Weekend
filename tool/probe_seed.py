"""Probe helpers before seeding demo profiles (development-only).

Checks Pillow availability, the interests catalogue, and any pre-existing demo
users so seeding is idempotent.
"""
import json
import os
import pathlib
import urllib.error
import urllib.request

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"
ROOT = pathlib.Path(__file__).resolve().parents[1]
env = {}
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if s and not s.startswith("#") and "=" in s:
        k, v = s.split("=", 1)
        env[k.strip()] = v.strip()


def sql(q):
    data = json.dumps({"query": q}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=data,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:800]}


try:
    import PIL  # noqa: F401
    print("Pillow: AVAILABLE", PIL.__version__)
except Exception as exc:  # pragma: no cover
    print("Pillow: MISSING", exc)

print("=== interests table columns ===")
print(json.dumps(sql(
    "select column_name,data_type from information_schema.columns "
    "where table_schema='public' and table_name='interests' order by ordinal_position"
))[:800])

print("=== interests sample ===")
print(json.dumps(sql("select * from public.interests limit 12"))[:1500])

print("=== existing demo users (wknd.demo) ===")
print(json.dumps(sql(
    "select u.email, p.display_name from auth.users u "
    "left join public.profiles p on p.id=u.id "
    "where u.email like 'wknd.demo%' order by u.email"
))[:1500])

print("=== user_settings columns (need show_online_now default) ===")
print(json.dumps(sql(
    "select column_name,data_type,column_default from information_schema.columns "
    "where table_schema='public' and table_name='user_settings' "
    "and column_name in ('user_id','show_online_now','incognito_mode','snooze_mode')"
))[:1200])
