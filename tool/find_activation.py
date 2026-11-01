"""Find what drives dating_profile_activated: triggers + photo minimum."""
import json
import os
import pathlib
import urllib.error
import urllib.request

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"


def run(title, q):
    data = json.dumps({"query": q}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=data,
        headers={"Authorization": "Bearer " + TOKEN,
                 "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = {"error": e.code, "body": e.read().decode()[:400]}
    print(f"\n=== {title} ===")
    if not isinstance(body, list):
        print(json.dumps(body)[:600])
        return
    for row in body:
        d = row.get("data", row)
        print("  ", json.dumps(d)[:1400])


run("triggers on profiles", """
select tgname, pg_get_triggerdef(oid) as d
from pg_trigger where tgrelid='public.profiles'::regclass and not tgisinternal
""")

run("triggers on profile_photos", """
select tgname, pg_get_triggerdef(oid) as d
from pg_trigger where tgrelid='public.profile_photos'::regclass and not tgisinternal
""")

run("has_minimum_photos + activation for demo1", """
select has_minimum_photos, dating_profile_activated, is_active,
       (select count(*) from public.profile_photos pp
         where pp.user_id=profiles.id) as all_photos,
       (select count(*) from public.profile_photos pp
         where pp.user_id=profiles.id and pp.moderation_status='approved') as appr
from public.profiles
where display_name='Aisha N'
""")

run("functions mentioning dating_profile_activated", """
select proname from pg_proc
where prosrc ilike '%dating_profile_activated%' limit 20
""")
