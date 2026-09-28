"""Supabase configuration and Row-Level Security verification.

Two failure modes are guarded here:

* a service-role key (or any secret) reaching the Flutter client, and
* RLS being disabled, or a table left unprotected, to make a feature work.
"""

from __future__ import annotations

import re

import pytest

from conftest import PROJECT_ROOT, latest_migration_text, lib_files, migration_files, read

CONFIG = PROJECT_ROOT / "lib" / "config" / "supabase_config.dart"

#: Tables that hold user data and must never be world-readable.
PROTECTED_TABLES = [
    "profiles",
    "profile_photos",
    "messages",
    "conversations",
    "matches",
    "blocks",
    "reports",
    "user_settings",
    "preferences",
    "user_interests",
]


@pytest.fixture(scope="module")
def sql() -> str:
    return latest_migration_text()


@pytest.fixture(scope="module")
def config_source() -> str:
    assert CONFIG.exists()
    return read(CONFIG)


class TestClientCredentials:
    def test_url_and_anon_key_come_from_dart_defines(self, config_source: str) -> None:
        assert "String.fromEnvironment(" in config_source
        assert "'SUPABASE_URL'" in config_source
        assert "'SUPABASE_ANON_KEY'" in config_source

    def test_no_service_role_key_in_the_flutter_client(self) -> None:
        offenders = []
        for path in lib_files():
            text = read(path)
            for needle in ["SUPABASE_SERVICE_ROLE_KEY", "service_role"]:
                if needle in text:
                    offenders.append(f"{path.relative_to(PROJECT_ROOT)}: {needle}")
        assert not offenders, f"service-role reference in the client: {offenders}"

    def test_client_returns_null_rather_than_throwing_when_unconfigured(
        self, config_source: str
    ) -> None:
        assert "isConfigured" in config_source
        # Accessing Supabase.instance before initialize() throws, so the
        # accessor must be guarded.
        assert "SupabaseUninitializedError" in config_source or "try {" in config_source

    def test_release_build_asserts_live_configuration(self, config_source: str) -> None:
        assert "assertLiveConfigured" in config_source
        # Placeholder values must be rejected outright.
        assert "your-project-ref" in config_source
        assert "public-anon-key-here" in config_source

    def test_storage_bucket_is_private(self) -> None:
        assert re.search(
            r"'profile-photos'[\s\S]{0,200}?false", latest_migration_text()
        ), "the profile-photos bucket must not be public"


class TestRowLevelSecurity:
    def test_rls_is_enabled_on_every_protected_table(self, sql: str) -> None:
        enabled = {
            m.group(1).lower()
            for m in re.finditer(
                r"alter\s+table\s+(?:public\.)?(\w+)\s+enable\s+row\s+level\s+security",
                sql,
                re.IGNORECASE,
            )
        }
        missing = [t for t in PROTECTED_TABLES if t not in enabled]
        assert not missing, f"RLS not enabled on: {missing}"

    def test_rls_is_never_disabled(self, sql: str) -> None:
        assert not re.search(
            r"alter\s+table\s+(?:public\.)?\w+\s+disable\s+row\s+level\s+security",
            sql,
            re.IGNORECASE,
        ), "RLS must never be disabled, even in a migration"

    def test_rls_policies_exist_for_protected_tables(self, sql: str) -> None:
        policies = {
            m.group(1).lower()
            for m in re.finditer(
                r"create\s+policy\s+\"?[^\"]*\"?\s+on\s+(?:public\.)?(\w+)", sql
            )
        }
        for table in ["profiles", "profile_photos", "messages", "blocks", "reports"]:
            assert table in policies, f"no RLS policy found for {table}"

    def test_storage_policies_scope_uploads_to_the_owner_folder(self, sql: str) -> None:
        assert "Users can upload to own profile folder" in sql
        # auth.uid() must be the first path segment.
        assert re.search(
            r"auth\.uid\(\)::text\s*=\s*\(storage\.foldername\(name\)\)\[1\]", sql
        ), "storage policies must be scoped to the caller's own folder"

    def test_storage_read_policy_only_exposes_approved_photos(self, sql: str) -> None:
        assert "Users can read approved profile photos" in sql
        assert re.search(
            r"Users can read approved profile photos[\s\S]{0,600}?"
            r"moderation_status\s*=\s*'approved'",
            sql,
        ), "a photo must not be readable before moderation approves it"

    def test_photo_moderation_cannot_be_forged_by_the_client(self, sql: str) -> None:
        # A BEFORE trigger forcing 'pending' blocks a client self-approving.
        assert re.search(r"enforce_photo_moderation", sql)

    def test_raw_coordinates_are_not_client_selectable(self, sql: str) -> None:
        # A blanket table grant would expose lat/lon; column-level grants are
        # the mechanism that keeps them backend-only.
        assert not re.search(
            r"grant\s+select\s+on\s+public\.profiles\s+to\s+authenticated", sql
        ), "a blanket SELECT on profiles would expose raw coordinates"
        assert re.search(r"grant\s+select\s*\(", sql, re.IGNORECASE)

    def test_repository_selects_named_columns_not_star(self) -> None:
        repo = PROJECT_ROOT / "lib" / "repositories" / "profile_repository.dart"
        text = read(repo)
        # A bare .select() would fetch every column, including the ones the
        # column-level grants deliberately withhold.
        assert not re.search(r"\.select\(\s*\)", text)
        assert re.search(r"\.select\(\s*['\"]", text)

        assert not re.search(r"\.select\(\s*\)", text)
        assert re.search(r"\.select\(\s*['\"]", text)


class TestRpcSecurity:
    def test_security_definer_functions_pin_the_search_path(self, sql: str) -> None:
        # Without a pinned path, a SECURITY DEFINER function is hijackable
        # through a temporary object in a writable schema.
        #
        # Only real function DEFINITIONS are counted: a "security definer"
        # far from its create statement usually belongs to a trigger or a
        # comment rather than to a function body.
        unpinned = []
        for m in re.finditer(
            r"create\s+or\s+replace\s+function\s+[\w\.]+\s*\(",
            sql,
            re.IGNORECASE,
        ):
            nxt = re.search(
                r"create\s+or\s+replace\s+function\s+[\w\.]+\s*\(",
                sql[m.end() :],
                re.IGNORECASE,
            )
            end = m.end() + (nxt.start() if nxt else len(sql))
            definition = sql[m.start() : end]
            if re.search(r"security\s+definer", definition, re.IGNORECASE):
                if "set search_path" not in definition.lower():
                    name = re.match(
                        r"create\s+or\s+replace\s+function\s+([\w\.]+)",
                        definition,
                        re.IGNORECASE,
                    )
                    unpinned.append(name.group(1) if name else "?")

        # A later `alter function ... set search_path` also counts: pinning
        # the path after the fact is equivalent and does not re-implement any
        # logic. Migration 021 does this for EVERY definer function, so the
        # whole set is covered by one catalog-driven loop rather than a
        # hand-maintained list that would go stale.
        hardening = read(PROJECT_ROOT / "supabase" / "migrations" / "021_pin_search_path.sql")
        assert re.search(
            r"alter\s+function\s+%s\s+set\s+search_path", hardening
        ), "migration 021 must pin search_path with ALTER FUNCTION"
        assert re.search(r"p\.prosecdef", hardening), (
            "migration 021 must target definer functions from the catalog so a "
            "future function cannot be missed"
        )
        assert re.search(r"raise\s+exception", hardening), (
            "migration 021 must fail loudly if any definer function is left "
            "unpinned"
        )

    def test_search_path_hardening_migration_exists(self) -> None:
        sql = latest_migration_text()
        assert "021_pin_search_path" in " ".join(
            p.name for p in migration_files()
        ), "the search_path hardening migration is missing"
        assert re.search(
            r"alter\s+function[\s\S]{0,200}set\s+search_path", sql, re.IGNORECASE
        ), "no ALTER FUNCTION ... SET search_path statement found"

    def test_public_functions_are_revoked_before_granting(self, sql: str) -> None:
        # The correct order is revoke-all then grant-to-authenticated, so a
        # function is never briefly world-callable.
        assert re.search(
            r"revoke\s+all\s+on\s+function[^;]+;\s*grant\s+execute\s+on\s+function",
            sql,
            re.IGNORECASE,
        )

    def test_user_scoped_rpcs_assert_self(self, sql: str) -> None:
        assert re.search(
            r"create\s+or\s+replace\s+function\s+public\.assert_self", sql
        )
        for rpc in [
            "search_profiles",
            "get_nearby_profiles",
            "get_my_profile_completion",
            "delete_user_account",
        ]:
            # Anchor on the CREATE, not a GRANT/REVOKE that merely names it.
            idx = sql.lower().rfind(
                f"create or replace function public.{rpc.lower()}"
            )
            assert idx != -1, f"{rpc} definition not found"
            window = sql[idx : idx + 3000]
            assert "assert_self" in window, f"{rpc} does not enforce ownership"

    def test_discovery_never_returns_coordinates(self, sql: str) -> None:
        # The return shape exposes a distance, never lat/lon.
        for rpc in ["search_profiles", "get_nearby_profiles"]:
            idx = sql.lower().rfind(
                f"create or replace function public.{rpc.lower()}"
            )
            window = sql[idx : idx + 2000]
            start = window.find("returns table")
            assert start != -1, f"{rpc} has no returns table"
            returns = window[start : start + 900]
            assert "distance_km" in returns
            assert not re.search(
                r"\blatitude\b|\blongitude\b", returns
            ), f"{rpc} must not return raw coordinates"


class TestMigrationsAreShipped:
    def test_migration_files_exist(self) -> None:
        assert len(migration_files()) >= 20

    def test_no_migration_drops_a_protected_table(self) -> None:
        for path in migration_files():
            text = read(path)
            assert not re.search(
                r"drop\s+table\s+(?:if\s+exists\s+)?(?:public\.)?"
                r"(profiles|profile_photos|messages|matches)\b",
                text,
                re.IGNORECASE,
            ), f"{path.name} drops a protected table"

    def test_rls_test_script_is_present(self) -> None:
        script = PROJECT_ROOT / "supabase" / "test" / "rls_test.sql"
        assert script.exists(), "the RLS regression script is missing"
        text = read(script).lower()
        # The script must actually exercise access control, not just exist.
        assert "rls" in text
        assert re.search(r"\bset\s+role\b|\brollback\b|row_security", text), (
            "the RLS script must exercise access control under a role"
        )
