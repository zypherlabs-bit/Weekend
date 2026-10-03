"""Regression guards for the adults-only enforcement added 2026-10-02.

These exist because the age gate was CLIENT-SIDE only. `updateDateOfBirth`
threw a Dart exception, but the Supabase anon key is public by design and
migration 006 grants the authenticated role UPDATE on `date_of_birth`, so a
minor could simply call the REST API instead of the app.

The suite is static by construction (as documented in `conftest`): it proves the
SQL says the right thing, never that a database ran it. Applying and probing
the live database remains a separate, human-driven step.
"""

from __future__ import annotations

import re

import pytest

from conftest import (
    function_body,
    latest_migration_text,
    migration_files,
    read,
    strip_sql_comments,
)


@pytest.fixture(scope="module")
def sql() -> str:
    return strip_sql_comments(latest_migration_text())


@pytest.fixture(scope="module")
def nearby(sql: str) -> str:
    body = function_body(sql, "get_nearby_profiles")
    assert body is not None
    return body


@pytest.fixture(scope="module")
def search(sql: str) -> str:
    body = function_body(sql, "search_profiles")
    assert body is not None
    return body


class TestAgeWritePath:
    """An under-18 date of birth must be unrepresentable, whatever the client."""

    def test_adult_trigger_exists_on_profiles(self, sql: str) -> None:
        assert re.search(
            r"create\s+trigger\s+on_adult_date_of_birth\b[\s\S]*?"
            r"before\s+insert\s+or\s+update\s+of\s+date_of_birth\s+on\s+public\.profiles",
            sql,
            re.IGNORECASE,
        ), "no BEFORE INSERT OR UPDATE trigger guards profiles.date_of_birth"

    def test_trigger_covers_insert_as_well_as_update(self) -> None:
        # Signup goes through handle_new_user, which INSERTs the profile row.
        # An INSERT-only or UPDATE-only trigger would leave signup unguarded.
        m = re.search(
            r"create\s+trigger\s+on_adult_date_of_birth[\s\S]*?execute\s+function",
            latest_migration_text(),
            re.IGNORECASE,
        )
        assert m is not None
        head = m.group(0).lower()
        assert "before insert" in head and "date_of_birth" in head

    def test_trigger_rejects_under_18(self, sql: str) -> None:
        body = function_body(sql, "enforce_adult_date_of_birth")
        assert body is not None, "enforce_adult_date_of_birth() is missing"
        assert re.search(r"v_age\s*<\s*18", body), "no under-18 rejection"
        assert "raise exception" in body.lower(), "rejection must abort the write"

    def test_trigger_is_not_bypassed_for_service_role(self, sql: str) -> None:
        # `protect_profile_columns` (005) exempts service_role. Reusing that
        # shape here would reopen the hole for any future Edge Function.
        body = function_body(sql, "enforce_adult_date_of_birth")
        assert body is not None
        assert "service_role" not in body, (
            "the age trigger must apply to every role, including service_role"
        )

    def test_unknown_age_is_allowed_but_not_discoverable(self, sql: str) -> None:
        # A NULL date of birth is legitimate mid-signup, so it must not raise.
        body = function_body(sql, "enforce_adult_date_of_birth")
        assert body is not None
        assert re.search(r"if\s+new\.date_of_birth\s+is\s+null", body), (
            "NULL date of birth must be tolerated during onboarding"
        )

    def test_dob_is_frozen_once_the_profile_is_public(self, sql: str) -> None:
        assert re.search(
            r"create\s+trigger\s+on_freeze_date_of_birth\b[\s\S]*?"
            r"before\s+update\s+of\s+date_of_birth\s+on\s+public\.profiles",
            sql,
            re.IGNORECASE,
        ), "date of birth can still be changed after activation"
        body = function_body(sql, "freeze_date_of_birth")
        assert body is not None
        assert "dating_profile_activated" in body


class TestMinorCannotMatchOrMessage:
    def test_is_adult_user_requires_a_proven_age(self, sql: str) -> None:
        body = function_body(sql, "is_adult_user")
        assert body is not None, "is_adult_user() is missing"
        assert "date_of_birth is not null" in body, "unknown age must fail closed"
        assert re.search(r">=\s*18", body), "no 18+ floor"
        assert "deleted_at is null" in body, "a deleted profile is not an adult"

    def test_record_like_checks_both_parties(self, sql: str) -> None:
        body = function_body(sql, "record_like")
        assert body is not None
        # Checking only the liker would still let a minor be liked.
        assert re.search(
            r"not\s+public\.is_adult_user\(v_me\)[\s\S]{0,80}"
            r"not\s+public\.is_adult_user\(p_target_id\)",
            body,
            re.IGNORECASE,
        ), "record_like must verify BOTH the liker and the target"

    def test_match_trigger_guards_the_conversation(self, sql: str) -> None:
        # The match row is what makes a conversation reachable, so the check
        # belongs on the trigger that creates it.
        body = function_body(sql, "check_mutual_like")
        assert body is not None
        assert "is_adult_user" in body, (
            "check_mutual_like can still create a match for a minor"
        )


class TestDiscoveryAdultFloor:
    @pytest.mark.parametrize("name", ["get_nearby_profiles", "search_profiles"])
    def test_floor_is_unconditional(self, sql: str, name: str) -> None:
        body = function_body(sql, name)
        assert body is not None
        assert re.search(
            r"and\s+p\.date_of_birth\s+is\s+not\s+null\s+"
            r"and\s+date_part\('years',\s*age\(p\.date_of_birth\)\)::int\s*>=?\s*18",
            body,
            re.IGNORECASE,
        ), f"{name} has no unconditional 18+ floor"

    @pytest.mark.parametrize("name", ["get_nearby_profiles", "search_profiles"])
    def test_caller_cannot_widen_the_floor_below_18(self, sql: str, name: str) -> None:
        body = function_body(sql, name)
        assert body is not None
        assert re.search(
            r"greatest\(\s*coalesce\(p_age_min,\s*18\)\s*,\s*18\s*\)",
            body,
            re.IGNORECASE,
        ), f"{name} lets a caller pass p_age_min below 18"

    @pytest.mark.parametrize("name", ["get_nearby_profiles", "search_profiles"])
    def test_no_defaulted_age(self, sql: str, name: str) -> None:
        body = function_body(sql, name)
        assert body is not None
        assert "else 25" not in body, "an unknown age must never be reported as 25"


class TestMigration027SchemaIntegrity:
    """027's shipped `get_nearby_profiles` referenced columns that do not exist.

    Postgres does not validate a plpgsql body at CREATE time, so the function
    compiled and every call raised at runtime - a silent, total discovery
    outage. These assertions exist because static analysis and unit tests with
    a mocked client both missed it.
    """

    # `profiles` has `id` (not user_id) and stores latitude/longitude as double
    # precision. age / interests / primary_photo_path are derived per row.
    FORBIDDEN_IN_NEARBY = [
        "prof.user_id",
        "prof.age",
        "prof.location",
        "prof.primary_photo_path",
        "prof.interests",
    ]

    @pytest.mark.parametrize("needle", FORBIDDEN_IN_NEARBY)
    def test_no_phantom_columns(self, nearby: str, needle: str) -> None:
        assert needle not in nearby, (
            f"get_nearby_profiles references {needle}, which is not a column "
            "of public.profiles; it would raise at runtime"
        )

    def test_passes_uses_its_real_column_names(self, nearby: str) -> None:
        # `passes` is (user_id, target_id) per migration 001.
        assert "passer_id" not in nearby and "passed_id" not in nearby
        assert "public.passes" in nearby

    def test_signature_matches_what_the_client_calls(self, nearby: str) -> None:
        full = latest_migration_text()
        idx = full.lower().rfind(
            "create or replace function public.get_nearby_profiles"
        )
        window = full[idx : idx + 600]
        for param in (
            "p_user_id",
            "p_limit",
            "p_offset",
            "p_max_distance_km",
            "p_preferred_genders",
            "p_age_min",
            "p_age_max",
            "p_discovery_mode",
        ):
            assert param in window, f"get_nearby_profiles lost {param}"

    def test_returns_the_columns_the_client_reads(self, nearby: str) -> None:
        # DiscoveryRepository._mapSearchRow / loadDiscoveryProfiles read these.
        for col in (
            "profile_id",
            "display_name",
            "age",
            "gender",
            "bio",
            "city",
            "distance_km",
            "primary_photo_path",
            "interests",
            "compatibility_score",
        ):
            assert col in nearby, f"get_nearby_profiles no longer returns {col}"

    def test_no_travel_mode_column(self, nearby: str) -> None:
        # user_settings has travel_mode_enabled (016) but NO travel city.
        assert "s.travel_city" not in nearby
        assert "v_travel_city" not in nearby

    def test_discovery_mode_is_actually_used(self, nearby: str) -> None:
        assert "v_mode" in nearby
        assert re.search(r"v_mode\s+not\s+in\s*\(", nearby, re.IGNORECASE)
        assert "v_enforce_distance" in nearby


class TestSearchProfilesRegression:
    """028 patches 023's search_profiles rather than replacing it.

    An earlier hand-written replacement silently dropped the language and
    lifestyle filters, the ALL-semantics interest match, match_score ordering
    and page pagination. These guard the patch against drifting into a rewrite.
    """

    def test_hard_filters_all_present(self, search: str) -> None:
        for needle in (
            "p.gender = any(p_genders)",
            "ST_DWithin",
            "lower(btrim(p.city)) = lower(btrim(p_city))",
            "p.relationship_intent = any(p_relationship_intents)",
            "from unnest(p_interests)",
            "from unnest(p_languages)",
            "jsonb_each_text(p_lifestyle)",
        ):
            assert needle in search, f"search_profiles lost hard filter: {needle}"

    def test_exclusions_all_present(self, search: str) -> None:
        for needle in (
            "p.id <> p_user_id",
            "p.is_active",
            "p.deleted_at is null",
            "p.dating_profile_activated",
            "public.blocks",
            "public.passes",
            "public.likes",
            "public.reports",
            "public.matches",
        ):
            assert needle in search, f"search_profiles lost exclusion: {needle}"

    def test_pagination_and_scoring_survive(self, search: str) -> None:
        assert re.search(r"least\(greatest\(coalesce\(p_page_size", search)
        assert "limit v_limit offset v_offset" in search
        assert "match_score" in search

    def test_caller_is_still_the_subject(self, search: str) -> None:
        assert "assert_self" in search


class TestMigrationsWellFormed:
    def test_dollar_quotes_balanced(self) -> None:
        for path in migration_files():
            assert read(path).count("$$") % 2 == 0, f"unbalanced $$ in {path.name}"

    def test_numbering_still_ordered_and_unique(self) -> None:
        numbers = [
            int(m.group(1))
            for m in (
                re.match(r"^(\d+)_", p.name) for p in migration_files()
            )
            if m
        ]
        assert numbers == sorted(numbers)
        assert len(numbers) == len(set(numbers))

    def test_no_placeholder_scaffolding_left_behind(self) -> None:
        # A truncated/merged migration file once shipped with a dangling
        # placeholder where section 6 belonged.
        for path in migration_files():
            assert "PLACEHOLDER" not in read(path), f"{path.name} has a placeholder"
