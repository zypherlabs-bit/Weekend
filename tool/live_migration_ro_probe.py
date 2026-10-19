"""
Weekend -- READ-ONLY, signature-aware migration-presence probe.

Reuses the signature-parsing idea of tool/live_migration_probe.py but calls
ONLY functions whose bodies are known read-only (SELECT/RAISE), so it is safe
to run against production with the anon key:

  * every probe value is a type-appropriate synthetic constant,
  * mutating RPCs (record_like, ensure_interest, delete_user_account,
    mark_*, update_*, insert-*) are EXCLUDED by allowlist.

Oracle (PostgREST resolves BEFORE permission is checked):
  404 + PGRST202 -> not in the schema cache -> function does NOT exist
  401 / 403      -> resolved, then refused   -> function EXISTS
  400 / 200 / 5xx-> reached the body         -> function EXISTS

The last `create function` in supabase/migrations/*.sql wins (live should
match the newest definition once that migration is applied).
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"

CREATE_RE = re.compile(
    r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(", re.IGNORECASE
)

# Read-only by inspection of the migration bodies: they SELECT or RAISE only.
READONLY = {
    "get_user_profile", "get_user_photos",
    "search_profiles", "get_nearby_profiles", "get_nearby_profiles_v2",
    "get_matches_for_user", "get_received_likes", "get_notifications",
    "notification_unread_count",
    "minimum_profile_photos", "maximum_profile_photos",
    "get_my_profile_completion", "approved_photo_count",
    "is_adult_user", "get_referral_stats", "get_ad_for_user",
    "assert_self", "get_device_tokens_for_user", "get_crossed_paths",
    "try_parse_date",
}

SYNTH = {
    "uuid": "00000000-0000-0000-0000-000000000000",
    "integer": 1, "int": 1, "bigint": 1,
    "boolean": False, "bool": False,
    "text": "wkd", "name": "wkd",
    "double precision": 0.0, "numeric": 0.0, "real": 0.0,
    "jsonb": {}, "json": {},
    "timestamp with time zone": "2000-01-01T00:00:00Z",
    "timestamptz": "2000-01-01T00:00:00Z",
    "text[]": [], "uuid[]": [],
}

def env_vars() -> dict:
    out: dict = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def parse_signatures() -> dict:
    """name -> (params [(name,type)...], migration file) for the LAST def."""
    found: dict = {}
    for f in sorted(MIGRATIONS.glob("*.sql")):
        text = f.read_text(encoding="utf-8", errors="replace")
        for m in CREATE_RE.finditer(text):
            name = m.group(1)
            i, depth, start = m.end() - 1, 0, m.end() - 1
            while i < len(text):
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            raw = text[start + 1:i]
            params = []
            for part in raw.split(","):
                part = " ".join(part.split())
                if not part:
                    continue
                part = re.split(r"\bdefault\b", part, flags=re.IGNORECASE)[0].strip()
                bits = part.split()
                if len(bits) >= 2 and bits[0].startswith("p_"):
                    params.append((bits[0], bits[1].lower()))
            found[name] = (params, f.name)
    return found


def synth_body(params) -> dict:
    return {p: SYNTH.get(t, "wkd") for p, t in params}


def rpc(base: str, anon: str, fn: str, body: dict):
    req = urllib.request.Request(f"{base}/rest/v1/rpc/{fn}",
                                 data=json.dumps(body).encode(), method="POST")
    req.add_header("apikey", anon)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + anon)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return 0, f"{type(e).__name__}: {e}"


def main() -> int:
    v = env_vars()
    base, anon = v["SUPABASE_URL"], v["SUPABASE_ANON_KEY"]
    sigs = parse_signatures()
    todo = {n: s for n, s in sigs.items() if n in READONLY}
    print(f"=== READ-ONLY signature-aware probe against {base} ===")
    print(f"parsed {len(sigs)} definitions; probing {len(todo)} read-only names\n")

    present_by_mig: dict[str, list[str]] = {}
    absent_by_mig: dict[str, list[str]] = {}
    for name, (params, migfile) in sorted(todo.items(), key=lambda kv: kv[1][1]):
        st, txt = rpc(base, anon, name, synth_body(params))
        exists = not (st == 404 and "PGRST202" in txt)
        bucket = present_by_mig if exists else absent_by_mig
        bucket.setdefault(migfile, []).append(name)
        flag = "EXISTS" if exists else "ABSENT"
        extra = "" if exists else f"  {' '.join(txt.split())[:150]}"
        print(f"  {flag:<7} [{migfile[:42]:<44}] {name:<30} HTTP {st}{extra}")

    print("\n=== per-migration verdict (read-only markers only) ===")
    for migfile in sorted(set(present_by_mig) | set(absent_by_mig)):
        yes = present_by_mig.get(migfile, [])
        no = absent_by_mig.get(migfile, [])
        if yes and not no:
            verdict = "APPLIED"
        elif yes and no:
            verdict = "PARTIAL / signature drift"
        else:
            verdict = "NOT APPLIED (or not in schema cache)"
        print(f"  {migfile:<46} {verdict}")
        if verdict != "APPLIED":
            print(f"      present: {yes or '-'}")
            print(f"      absent : {no or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
