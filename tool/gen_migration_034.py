"""Generate migration 034 from the search_profiles block in 031, with the fix.

031's 21-argument search_profiles joins a lateral spotlight subquery aliased
`sw` but the subquery selects `1 as mid`, so every reference to `sw.id` (the
SOFT spotlight ranking and the is_spotlit output column) raises
`column sw.id does not exist` at runtime - the hardened discovery feed returns
HTTP 400. The 13-argument legacy overload (used by the advanced-search screen)
is unaffected, which is why the defect stayed hidden behind a partially working
feed.

Rather than rewrite an already-applied migration, this emits 034 as an
idempotent CREATE OR REPLACE (the OUT row type is unchanged, so no drop is
needed). Usage: python tool/gen_migration_034.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "supabase" / "migrations" / "031_unified_discovery_entitlements_and_modes.sql"
DST = ROOT / "supabase" / "migrations" / "034_fix_spotlight_lateral_alias.sql"

HEADER = """-- ============================================================
-- 034 - fix: search_profiles (21-arg) spotlight lateral alias
-- ============================================================
--
-- 031 introduced the SOFT spotlight ranking in the 21-argument
-- public.search_profiles by joining
--
--     left join lateral (... limit 1) sw on true
--
-- but the lateral's select list aliased its constant as `mid`, while the
-- outer query reads `sw.id` twice (the +40 ranking term and the is_spotlit
-- output column). Postgres resolves those at execution time, so the function
-- compiled cleanly and then failed on every call with
--
--     ERROR: 42703: column sw.id does not exist
--
-- i.e. the hardened discovery feed returned HTTP 400 while the 13-argument
-- legacy overload (still used by the advanced-search screen) kept working,
-- which masked the defect.
--
-- This migration is a single CREATE OR REPLACE with `select 1 as id`, matching
-- the identical lateral already used in get_nearby_profiles. The OUT row type
-- is unchanged, so no DROP is required and nothing else is touched.
--
-- Additive and idempotent: safe to re-run.

"""


def main() -> int:
    text = SRC.read_text(encoding="utf-8").replace("\r\n", "\n")
    lines = text.split("\n")

    start = next(i for i, l in enumerate(lines)
                 if l.startswith("create or replace function public.search_profiles("))
    end = next(i for i, l in enumerate(lines)
               if i > start and l.strip() == ") to authenticated;") + 1
    block = "\n".join(lines[start:end])

    if "select 1 as mid from public.spotlight_windows w" not in block:
        print("expected 'select 1 as mid' not found - 031 may already be fixed")
        return 1
    fixed = block.replace("select 1 as mid from public.spotlight_windows w",
                          "select 1 as id from public.spotlight_windows w")
    if fixed.count("sw.id") != block.count("sw.id"):
        print("refusing: sw.id count changed unexpectedly")
        return 1

    DST.write_text(HEADER + fixed + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {DST.relative_to(ROOT)} ({len(fixed)} chars, "
          f"{fixed.count('sw.id')} sw.id references preserved)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
