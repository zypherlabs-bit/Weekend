"""Inspect the seeded demo rows against every get_nearby_profiles filter."""
import json
import os
import pathlib
import urllib.error
import urllib.request

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"

q = """
select u.email, p.display_name, p.is_active, p.deleted_at,
       p.dating_profile_activated, length(btrim(coalesce(p.display_name,''))) as namelen,
       p.date_of_birth, date_part('years', age(p.date_of_birth)) as age,
       p.gender, p.latitude, p.longitude, p.city,
       p.verification_status, p.last_active_at,
       (p.last_active_at > now() - interval '7 days') as active7d,
       us.snooze_mode, us.snooze_until, us.incognito_mode,
       (select count(*) from public.profile_photos pp
         where pp.user_id = p.id and pp.moderation_status='approved') as approved_photos,
       (select count(*) from public.user_interests ui
         where ui.user_id = p.id) as interests
from auth.users u
join public.profiles p on p.id = u.id
left join public.user_settings us on us.user_id = p.id
where u.email like 'wknd.demo%'
order by u.email
"""
data = json.dumps({"query": q}).encode()
req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{REF}/database/query",
    data=data,
    headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        body = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    body = {"error": e.code, "body": e.read().decode()[:500]}

rows = body if isinstance(body, list) else []
if not rows:
    print("NO ROWS:", json.dumps(body)[:600])
for row in rows:
    d = row.get("data", row)
    print(f"\n{d.get('email')}  name={d.get('display_name')!r}")
    print(f"   is_active={d.get('is_active')} deleted_at={d.get('deleted_at')} "
          f"activated={d.get('dating_profile_activated')} namelen={d.get('namelen')}")
    print(f"   dob={d.get('date_of_birth')} age={d.get('age')} gender={d.get('gender')!r}")
    print(f"   lat={d.get('latitude')} lon={d.get('longitude')} city={d.get('city')!r}")
    print(f"   snooze={d.get('snooze_mode')}/{d.get('snooze_until')} "
          f"incognito={d.get('incognito_mode')} settings_row_missing={d.get('snooze_mode') is None}")
    print(f"   approved_photos={d.get('approved_photos')} interests={d.get('interests')} "
          f"last_active={d.get('last_active_at')}")
