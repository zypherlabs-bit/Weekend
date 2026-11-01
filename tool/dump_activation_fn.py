"""Dump the two photo-sync functions to learn the photo minimum."""
import json
import os
import pathlib
import urllib.error
import urllib.request

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"

q = """
select proname, pg_get_functiondef(oid) as d
from pg_proc
where proname in ('sync_dating_profile_activation','sync_profile_photo_counters')
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
    body = {"error": e.code, "body": e.read().decode()[:400]}

if not isinstance(body, list):
    print(json.dumps(body)[:600])
else:
    for row in body:
        d = row.get("data", row)
        print(f"\n{'='*60}\n{d.get('proname')}\n{'='*60}")
        print(d.get("d"))
