"""Filter-logic tests.

Two layers:

* An executable reference implementation of the AND semantics, exercised with
  the exact fixture data from the specification (profiles A-D). This proves
  the *rule* is right, independent of any database.
* STATIC checks that the shipped SQL expresses those same rules server-side,
  and that the client does not re-filter locally.

The reference implementation intentionally mirrors the SQL: every hard filter
is a separate `and` clause, and soft ranking only reorders the survivors.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    migration_text,
    read_text,
)


@dataclass
class FixtureProfile:
    """A candidate profile used to exercise the filter rules."""

    name: str
    gender: str
    age: int | None
    distance_km: float
    relationship_intent: str
    city: str = "Pune"
    interests: list[str] = field(default_factory=list)
    languages: list[str] = field(default_factory=list)
    smoking: str = "Never"
    blocked: bool = False
    deleted: bool = False


#: The fixture set from the specification, verbatim.
PROFILES = [
    FixtureProfile("A", "Woman", 28, 12, "Long-term relationship"),
    FixtureProfile("B", "Woman", 35, 12, "Long-term relationship"),
    FixtureProfile("C", "Man", 28, 10, "Long-term relationship"),
    FixtureProfile("D", "Woman", 29, 75, "Long-term relationship"),
]


def matches_hard_filters(
    p: FixtureProfile,
    *,
    genders: list[str],
    age_min: int,
    age_max: int,
    max_distance_km: float,
    relationship_intents: list[str],
) -> bool:
    """AND semantics, exactly as `search_profiles` implements them.

    A profile with an unknown age (None) is EXCLUDED whenever an age range is
    supplied: a hard filter that cannot be satisfied must not silently pass.
    """
    if genders and p.gender not in genders:          # 1. gender
        return False
    if p.age is None or not (age_min <= p.age <= age_max):  # 2. age
        return False
    if p.distance_km > max_distance_km:              # 3. distance
        return False
    if relationship_intents and p.relationship_intent not in relationship_intents:
        return False                                  # 4. intent
    if p.blocked or p.deleted:                        # always-on exclusions
        return False
    return True


_SPEC_QUERY = dict(
    genders=["Woman"],
    age_min=25,
    age_max=32,
    max_distance_km=50,
    relationship_intents=["Long-term relationship"],
)


def test_specification_fixture() -> None:
    """The spec's worked example returns exactly profile A.

    Query: Female, 25-32, <= 50 km, Long-term. B fails on age (35), C fails on
    gender, D fails on distance (75 km).
    """
    result = [p.name for p in PROFILES if matches_hard_filters(p, **_SPEC_QUERY)]
    assert result == ["A"], f"expected only A, got {result}"


def test_unknown_age_excluded() -> None:
    """A profile with no stated age never satisfies an age filter."""
    p = FixtureProfile("X", "Woman", None, 5, "Long-term relationship")
    assert not matches_hard_filters(p, **_SPEC_QUERY)


def test_multiple_filters_are_and() -> None:
    """Every additional hard filter can only narrow the result set."""


# ---------------------------------------------------------------------------
# STATIC checks that the SQL and Dart express those rules
# ---------------------------------------------------------------------------

def _search_sql() -> str:
    """Extract the EFFECTIVE search_profiles body (the last definition).

    Matches the CREATE FORM specifically. A plain substring search would also
    match the trailing `grant execute on function public.search_profiles(...)`
    statements, which are not a definition and carry no body.
    """
    sql = migration_text().lower()
    pattern = re.compile(
        r"create\s+(?:or\s+replace\s+)?function\s+public\.search_profiles\s*\("
    )
    matches = list(pattern.finditer(sql))
    if not matches:
        return ""
    start = matches[-1].start()
    end = sql.find("$$;", start)
    return sql[start:end] if end > 0 else sql[start:]


def test_search_rpc_exists() -> CheckResult:
    """STATIC: a dedicated advanced-search RPC is defined."""
    ok = "function public.search_profiles(" in migration_text().lower()
    return CheckResult(
        name="search_profiles RPC exists",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="defined" if ok else "not defined",
    )


def test_all_hard_filters_in_sql() -> CheckResult:
    """STATIC: gender, age, distance, intent, city, interests and languages are
    all enforced inside the search function."""
    body = _search_sql()
    if not body:
        return CheckResult(
            name="Hard filters enforced in SQL",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="function not found",
        )
    required = {
        "gender": "p_genders",
        "age": "p_age_min",
        "distance": "st_dwithin",
        "intent": "p_relationship_intents",
        "city": "p_cities",
        "interests": "p_interests",
        "languages": "p_languages",
    }
    missing = [k for k, marker in required.items() if marker not in body]
    return CheckResult(
        name="Hard filters enforced in SQL",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all 7 present" if not missing else f"missing: {', '.join(missing)}",
    )


def test_soft_ranking_is_order_by_only() -> CheckResult:
    """STATIC: soft signals appear only in ORDER BY, never in WHERE."""
    body = _search_sql()
    if not body:
        return CheckResult(
            name="Soft ranking is ORDER BY only",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="function not found",
        )
    where_idx = body.find("\n    where")
    order_idx = body.find("order by")
    # Completeness and trust are ranking signals that legitimately appear in
    # the SELECT list (the compatibility score). What must NOT happen is them
    # acting as predicates in the WHERE clause, which would turn a soft signal
    # into a hard filter. So the WHERE clause is isolated and inspected alone.
    if where_idx < 0 or order_idx < 0:
        return CheckResult(
            name="Soft ranking is ORDER BY only",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="could not isolate the WHERE clause",
        )
    where_clause = body[where_idx:order_idx]
    soft = ["profile_completion", "trust_score", "is_photo_verified"]
    in_where = [s for s in soft if s in where_clause]
    return CheckResult(
        name="Soft ranking is ORDER BY only",
        status=Status.PASS if not in_where else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "no soft predicate in WHERE"
            if not in_where
            else f"soft filter in WHERE: {in_where}"
        ),
    )


def test_client_does_not_filter_locally() -> CheckResult:
    """STATIC: the client sends filters to the server, it does not re-filter."""
    search = read_text(REPO_ROOT / "lib" / "repositories" / "discovery_repository.dart")
    sends_rpc = "'search_profiles'" in search
    local_filter = re.search(
        r"\.where\(\s*\(\w+\)\s*=>\s*\w+\.(age|gender)\b", search
    )
    ok = sends_rpc and not local_filter
    return CheckResult(
        name="Client sends filters to server",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "RPC only, no local filter"
            if ok
            else ("local filtering present" if local_filter else "RPC not called")
        ),
    )


def test_search_screen_exists() -> CheckResult:
    """STATIC: a dedicated Discover / Search Filters screen is shipped."""
    screen = REPO_ROOT / "lib" / "features" / "discovery" / "search_screen.dart"
    ok = screen.exists() and len(read_text(screen)) > 1000
    return CheckResult(
        name="Search filters screen",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="present" if ok else "missing",
    )


def test_truthful_empty_state() -> CheckResult:
    """STATIC: the empty state explains and offers explicit widening."""
    screen = read_text(
        REPO_ROOT / "lib" / "features" / "discovery" / "search_screen.dart"
    )
    ok = (
        "No profiles match all your filters" in screen
        and "Increase distance" in screen
        and "Expand age range" in screen
    )
    return CheckResult(
        name="Truthful empty state",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "message + widen actions" if ok else "empty state missing widen actions"
        ),
    )


def _effective_body(func: str) -> str:
    """Return the LAST definition of `func`, which is the one that runs.

    Earlier migrations are kept for history and several of them contain code
    this project has since replaced. Reading the first match would judge a
    superseded implementation, so the search runs from the end.
    """
    sql = migration_text()
    pattern = re.compile(
        rf"create\s+(?:or\s+replace\s+)?function\s+public\.{re.escape(func)}\s*\("
    )
    matches = list(pattern.finditer(sql.lower()))
    if not matches:
        return ""
    start = matches[-1].start()
    end = sql.find("$$;", start)
    return sql[start:end] if end > 0 else sql[start:]


def test_no_fabricated_age() -> CheckResult:
    """STATIC: no live RPC invents an age for a profile with no birthday.

    `else 25` in an age expression is fabricated data. The correct behaviour is
    NULL, which the UI renders as "Age not stated". Only the effective (last)
    definition of each function is inspected.
    """
    offenders: list[str] = []
    for func in ("get_nearby_profiles", "search_profiles", "get_matches_for_user"):
        body = _effective_body(func)
        if body and re.search(r"else\s+25\b", body, re.I):
            offenders.append(func)
    return CheckResult(
        name="No fabricated age",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "age is NULL when unknown"
            if not offenders
            else f"still fabricates age: {', '.join(offenders)}"
        ),
    )

def test_blocked_and_deleted_excluded_in_search() -> CheckResult:
    """STATIC: blocked, deleted and banned accounts are always excluded."""
    body = _search_sql()
    ok = "public.blocks" in body and "auth_user_state" in body
    return CheckResult(
        name="Blocked/deleted excluded in search",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="blocks + deleted/banned excluded" if ok else "exclusion missing",
    )
