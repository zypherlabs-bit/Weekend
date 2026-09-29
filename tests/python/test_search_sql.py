"""Static verification that the shipped SQL really expresses the rules.

The RUNTIME model in ``test_filter_logic`` proves the *semantics*; this
module proves the *implementation* matches. Both are required: a model can
be correct while the deployed SQL is not.
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
    return latest_migration_text()


@pytest.fixture(scope="module")
def search_body(sql: str) -> str:
    raw = function_body(sql, "search_profiles")
    assert raw is not None, "search_profiles RPC not found in any migration"
    return strip_sql_comments(raw)


@pytest.fixture(scope="module")
def nearby_body(sql: str) -> str:
    raw = function_body(sql, "get_nearby_profiles")
    assert raw is not None, "get_nearby_profiles not found in any migration"
    return strip_sql_comments(raw)


class TestMigrations:
    def test_migrations_directory_is_not_empty(self) -> None:
        files = migration_files()
        assert files, "no migrations found"
        assert len(files) >= 20, "expected the 020 migration to exist"

    def test_migrations_are_numbered_and_ordered(self) -> None:
        numbers = []
        for path in migration_files():
            m = re.match(r"^(\d+)_", path.name)
            if m:
                numbers.append(int(m.group(1)))
        assert numbers == sorted(numbers), "migration numbering is out of order"
        assert len(numbers) == len(set(numbers)), "duplicate migration numbers"

    def test_migrations_are_balanced(self) -> None:
        # An unbalanced $$ would fail at apply time; catching it here turns a
        # confusing production error into a clear test failure.
        for path in migration_files():
            text = read(path)
            assert text.count("$$") % 2 == 0, f"unbalanced $$ in {path.name}"


class TestSearchProfilesRpc:
    def test_rpc_exists(self, search_body: str) -> None:
        assert "return query" in search_body

    def test_rpc_is_security_definer_with_pinned_search_path(self, sql: str) -> None:
        idx = sql.lower().find("create or replace function public.search_profiles")
        assert idx != -1
        window = sql[idx : idx + 5000].lower()
        assert "security definer" in window
        assert "set search_path = public" in window

    def test_rpc_enforces_caller_is_the_subject(self, search_body: str) -> None:
        # Without this the function is a database-wide enumeration oracle.
        assert "assert_self" in search_body

    def test_all_hard_filters_present(self, search_body: str) -> None:
        required = {
            "gender": "p.gender = any(p_genders)",
            "age_min": "p_age_min",
            "age_max": "p_age_max",
            "distance": "ST_DWithin",
            "city": "lower(btrim(p.city)) = lower(btrim(p_city))",
            "relationship_intent": "p.relationship_intent = any("
            "p_relationship_intents)",
            "interests": "from unnest(p_interests) as required(name)",
            "languages": "from unnest(p_languages) as required(lang)",
            "lifestyle": "jsonb_each_text(p_lifestyle)",
        }
        missing = [name for name, needle in required.items() if needle not in search_body]
        assert not missing, f"search_profiles is missing hard filters: {missing}"

    def test_unknown_age_is_excluded_not_defaulted(self, search_body: str) -> None:
        # The old implementation reported every unknown DOB as age 25, which
        # silently satisfied any 25-32 request.
        assert "else 25" not in search_body
        assert "p.date_of_birth is not null" in search_body

    def test_lifecycle_and_exclusions_present(self, search_body: str) -> None:
        for needle in [
            "p.id <> p_user_id",
            "p.is_active",
            "p.deleted_at is null",
            "p.dating_profile_activated",
            "public.blocks",
            "public.passes",
            "public.likes",
            "public.reports",
            "public.matches",
        ]:
            assert needle in search_body, f"missing exclusion: {needle}"

    def test_no_percentage_threshold_in_eligibility(self, search_body: str) -> None:
        # A score gate in the WHERE clause would be partial-credit filtering.
        assert not re.search(
            r"(match_score|compatibility_score|soft_score)\s*(>=|>|<=|<)\s*\d",
            search_body,
            re.IGNORECASE,
        )
        assert not re.search(r"score\s*>=\s*\d+\s*/\s*\d+", search_body, re.IGNORECASE)

    def test_score_is_only_used_for_ordering(self, search_body: str) -> None:
        assert "match_score" in search_body
        assert re.search(r"order by[\s\S]*soft_score", search_body, re.IGNORECASE)

    def test_pagination_is_bounded(self, search_body: str) -> None:
        assert re.search(r"least\(greatest\(coalesce\(p_page_size", search_body)
        assert "limit v_limit offset v_offset" in search_body

    def test_interests_require_all_not_some(self, search_body: str) -> None:
        # "not exists (a required interest that is missing)" == ALL semantics.
        assert "where not exists" in search_body
        start = search_body.find("from unnest(p_interests)")
        assert start != -1
        block = search_body[start : start + 700]
        assert "where not exists" in block


class TestGetNearbyProfilesFixes:
    """The lat/lon swap and fabricated-age defects must stay fixed."""

    def test_point_arguments_are_longitude_then_latitude(self, nearby_body: str) -> None:
        # PostGIS ST_Point(x, y) is ST_Point(longitude, latitude). The
        # viewer's own position must follow the same order as the candidates'.
        assert re.search(
            r"ST_Point\(\s*v_viewer_lon\s*,\s*v_viewer_lat\s*\)", nearby_body
        ), "viewer point must be ST_Point(longitude, latitude)"

    def test_no_transposed_viewer_point(self, nearby_body: str) -> None:
        # The 011 bug was ST_Point((select latitude ...), (select longitude ...)).
        assert not re.search(
            r"ST_Point\(\s*v_viewer_lat\s*,\s*v_viewer_lon\s*\)", nearby_body
        )
        assert not re.search(
            r"ST_Point\(\s*\(select latitude", nearby_body, re.IGNORECASE
        )

    def test_candidate_point_uses_longitude_first(self, nearby_body: str) -> None:
        assert re.search(
            r"ST_Point\(\s*p\.longitude\s*,\s*p\.latitude\s*\)", nearby_body
        )

    def test_fabricated_age_removed(self, nearby_body: str) -> None:
        assert "else 25" not in nearby_body
        assert "date_of_birth is not null" in nearby_body

    def test_discovery_mode_is_actually_used(self, nearby_body: str) -> None:
        # The parameter used to appear in the signature and be ignored.
        assert "v_mode" in nearby_body
        assert re.search(r"v_mode\s+not\s+in\s*\(", nearby_body, re.IGNORECASE)
        assert "v_enforce_distance" in nearby_body

    def test_photo_and_lifecycle_gates_present(self, nearby_body: str) -> None:
        assert "p.dating_profile_activated" in nearby_body
        assert "p.is_active" in nearby_body
        assert "p.deleted_at is null" in nearby_body

    def test_signature_is_backwards_compatible(self, nearby_body: str) -> None:
        # The Flutter client calls this exact signature; changing it would
        # require a coordinated deploy.
        full = latest_migration_text()
        idx = full.lower().rfind(
            "create or replace function public.get_nearby_profiles"
        )
        signature = full[idx : idx + 600]
        for param in [
            "p_user_id",
            "p_limit",
            "p_offset",
            "p_max_distance_km",
            "p_preferred_genders",
            "p_age_min",
            "p_age_max",
            "p_discovery_mode",
        ]:
            assert param in signature, f"signature lost {param}"


class TestPhotoMinimumRule:
    def test_minimum_is_defined_in_sql(self, sql: str) -> None:
        assert re.search(
            r"create or replace function public\.minimum_profile_photos\(\)", sql
        )
        body = function_body(sql, "minimum_profile_photos")
        assert body is not None
        # The threshold is configurable (profile_requirements), but its shipped
        # default must still be exactly 4 and the function must read it rather
        # than hard-code a literal.
        assert re.search(
            r"insert\s+into\s+public\.profile_requirements[^;]*values\s*\(\s*true\s*,\s*4\s*,",
            sql,
            re.IGNORECASE | re.DOTALL,
        ), "the configured default must remain 4 photos"
        assert "profile_requirements" in body, (
            "minimum_profile_photos must read the configured value"
        )
        assert not re.search(r"select\s+4", body), (
            "the literal 4 was replaced by the configured value"
        )

    def test_only_approved_photos_count(self, sql: str) -> None:
        body = function_body(sql, "approved_photo_count")
        assert body is not None
        assert "moderation_status = 'approved'" in strip_sql_comments(body)

    def test_activation_flag_is_maintained_by_a_trigger(self, sql: str) -> None:
        body = function_body(sql, "sync_dating_profile_activation")
        assert body is not None
        assert "minimum_profile_photos()" in body
        assert re.search(
            r"create trigger on_photo_count_change[\s\S]*on public\.profile_photos",
            sql,
            re.IGNORECASE,
        )

    def test_profile_completion_rpc_reports_the_remaining_count(self, sql: str) -> None:
        body = function_body(sql, "get_my_profile_completion")
        assert body is not None
        assert "photos_remaining" in body
        assert "minimum_photos" in body
        assert "assert_self" in body

    def test_discovery_filters_on_the_activation_flag(self, sql: str) -> None:
        body = function_body(sql, "search_profiles")
        assert body is not None
        assert "p.dating_profile_activated" in strip_sql_comments(body)

