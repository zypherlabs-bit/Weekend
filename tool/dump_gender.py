"""Print the profiles_gender_check allowed set (development-only)."""
import json
import os
import pathlib
import urllib.error
import urllib.request

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"

q = ("select pg_get_constraintdef(oid) as d from pg_constraint "
     "where conname = 'profiles_gender_check'")
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
print(json.dumps(body, indent=2))
