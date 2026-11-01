"""Dump the live get_nearby_profiles body + probe location (development helper).

Prints the SECURITY DEFINER function source so we know the exact filters a
seeded profile must satisfy, plus the probe account's stored coordinates.
Development-only: reads the management token from %TEMP%\\sbp_token.txt.
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
        return {"error": e.code, "body": e.read().decode()[:1500]}


print("=== get_nearby_profiles SOURCE ===")
src = sql(
    "select pg_get_functiondef(p.oid) as d from pg_proc p "
    "join pg_namespace n on n.oid=p.pronamespace "
    "where n.nspname='public' and p.proname='get_nearby_profiles'"
)
if isinstance(src, list):
    print(src[0].get("data", src[0]).get("d", ""))
else:
    print(src)

print("=== probe profile row ===")
row = sql(
    "select p.id, p.display_name, p.latitude, p.longitude, p.city, p.locality, "
    "p.country, p.is_active, p.dating_profile_activated, p.verification_status, "
    "p.last_active_at, p.has_minimum_photos, u.email from public.profiles p "
    "join auth.users u on u.id = p.id "
    f"where u.email = '{env.get('PROBE_EMAIL','')}'"
)
print(json.dumps(row, indent=2)[:3000])
