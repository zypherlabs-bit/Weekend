"""
Weekend -- DECISIVE migration-presence probe (signature aware).

Why this file exists
--------------------
PostgREST resolves an RPC by matching the EXACT named parameter list of an
overload. Two things therefore make naive probing lie:

  1. Sending `{}` returns PGRST202 even for functions that definitely exist,
     because they all declare named parameters.
  2. Sending a SUPERSET of parameters (p_user_id + p_target_id + ...) also
     returns PGRST202, because no overload accepts that exact combination.

Only a call whose parameter names match one declared overload exactly can
answer the existence question. This file therefore parses the signature
straight out of `supabase/migrations/*.sql` and calls with exactly those
names, so the applied/not-applied line is derived from the repository's own
source of truth rather than guessed.

Existence oracle (404/401 split):
  404 + PGRST202 -> NOT in the schema cache -> function does not exist
  401 / 403      -> resolved, then refused     -> function exists
  400 / 200 / 5xx-> reached the function body   -> function exists

Uses only the public anon key. Never prints a token, password or UUID.
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
    r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(", re.IGNORECASE)

# Only the params we can safely synthesise a value for. Anything else is left
# out so the call resolves on the overload that the migration declared.
SYNTH = {
    "uuid": "00000000-0000-0000-0000-000000000000",
    "integer": 1,
    "int": 1,
    "boolean": False,
    "bool": False,
    "text": "wkd",
    "double precision": 0.0,
    "numeric": 0.0,
    "jsonb": {},
    "timestamptz": "2000-01-01T00:00:00Z",
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
    """name -> list of (params_tuple, migration_file) for the LAST definition."""
    found: dict = {}
    for f in sorted(MIGRATIONS.glob("*.sql")):
        text = f.read_text(encoding="utf-8", errors="replace")
        for m in CREATE_RE.finditer(text):
            name = m.group(1)
            # Walk forward from the '(' to its matching ')'.
            i = m.end() - 1
            depth, start = 0, i
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
                # drop a trailing "default ..." clause
                part = re.split(r"\bdefault\b", part, flags=re.IGNORECASE)[0].strip()
                bits = part.split()
                if len(bits) >= 2 and bits[0].startswith("p_"):
                    params.append((bits[0], bits[1].lower()))
            found[name] = (params, f.name)
    return found


def synth_body(params) -> dict:
    body = {}
    for pname, ptype in params:
        body[pname] = SYNTH.get(ptype, "wkd")
    return body


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
    print(f"=== Signature-aware migration probe against {base} ===")
    print(f"parsed {len(sigs)} function definitions from supabase/migrations\n")

    rows = []
    for name, (params, migfile) in sorted(sigs.items(), key=lambda kv: kv[1][1]):
        if not params and migfile == "x":
            continue
        body = synth_body(params)
        st, txt = rpc(base, anon, name, body)
        exists = not (st == 404 and "PGRST202" in txt)
        rows.append((migfile, name, exists, st, len(params)))

    applied = sorted({r[0] for r in rows if r[2]})
    absent_migs = sorted({r[0] for r in rows if not r[2]})

    print(f"{'':4}{'migration':<46}{'status':<10}HTTP")
    print("-" * 74)
    for migfile, name, exists, st, n in rows:
        flag = "EXISTS" if exists else "ABSENT"
        print(f"{'':4}{migfile[:44]:<46}{flag:<10}{st}")

    print("\n=== summary ===")
    print("migrations with at least one function present:", applied or "none")
    missing = [m for m in sorted(set(r[0] for r in rows)) if m not in applied]
    print("migrations with NO function present          :", missing or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())