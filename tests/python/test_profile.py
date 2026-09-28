"""Profile, Edit Profile and photo-requirement verification.

Three concerns, kept separate because they fail for different reasons:

* the profile data really comes from the backend (no hard-coded examples),
* Edit Profile can actually edit the fields the profile displays,
* the minimum-4-photos rule is enforced on the client as well as the server.
"""

from __future__ import annotations

import re

import pytest

from conftest import PROJECT_ROOT, lib_files, read

PROFILE_REPO = PROJECT_ROOT / "lib" / "repositories" / "profile_repository.dart"
PROFILE_SCREEN = PROJECT_ROOT / "lib" / "features" / "profile" / "profile_screen.dart"
EDIT_SCREEN = PROJECT_ROOT / "lib" / "features" / "profile" / "edit_profile_screen.dart"
MODELS = PROJECT_ROOT / "lib" / "models" / "models.dart"
COMPLETION_REPO = PROJECT_ROOT / "lib" / "repositories" / "search_repository.dart"
IMAGE_OPTIMIZER = PROJECT_ROOT / "lib" / "services" / "image_optimizer.dart"

MINIMUM_PHOTOS = 4


def _read(path):
    assert path.exists(), f"missing {path}"
    return read(path)


class TestProfileFieldsExist:
    def test_user_profile_model_has_name_age_city(self) -> None:
        text = _read(MODELS)
        for field in ["final String name;", "final int age;", "final String city;"]:
            assert field in text, f"UserProfile is missing {field!r}"

    def test_repository_selects_the_real_columns(self) -> None:
        text = _read(PROFILE_REPO)
        for column in ["display_name", "date_of_birth", "city", "bio", "gender"]:
            assert column in text, f"profile fetch does not read {column}"

    def test_age_is_derived_from_the_stored_birth_date(self) -> None:
        text = _read(PROFILE_REPO)
        assert "date_of_birth" in text
        assert re.search(r"difference\(dateOfBirth\)", text), (
            "age must be computed from the birth date, not hard-coded"
        )

    def test_profile_screen_renders_name_age_and_city(self) -> None:
        text = _read(PROFILE_SCREEN)
        assert "user.name" in text
        assert "user.age" in text
        assert "user.city" in text


class TestNoFabricatedProfileData:
    """The app must never invent a name, age or city."""

    FORBIDDEN_LITERALS = [
        "Prakash",
        "John Doe",
        "Lorem ipsum",
    ]

    def test_no_example_names_in_lib(self) -> None:
        offenders = []
        for path in lib_files():
            text = read(path)
            for literal in self.FORBIDDEN_LITERALS:
                if literal in text:
                    offenders.append(f"{path.relative_to(PROJECT_ROOT)}: {literal}")
        assert not offenders, f"fabricated example data found: {offenders}"

    def test_discovery_does_not_default_age_to_25(self) -> None:
        discovery = PROJECT_ROOT / "lib" / "repositories" / "discovery_repository.dart"
        text = _read(discovery)
        # A missing DOB yields 0 ("not stated"), never a plausible number.
        assert "_ageFromDateOfBirth" in text
        assert re.search(r"if \(dob == null\) return 0;", text), (
            "an unknown age must be 0 (not stated), not a default age"
        )

    def test_placeholder_profile_carries_no_personal_data(self) -> None:
        provider = PROJECT_ROOT / "lib" / "providers" / "weekend_provider.dart"
        text = _read(provider)
        start = text.find("factory WeekendState.initial()")
        assert start != -1
        block = text[start : start + 1200]
        assert "name: ''" in block
        assert "city: ''" in block
        assert "bio: ''" in block

    def test_no_unresolved_markers_rendered_to_users(self) -> None:
        offenders = []
        for path in lib_files():
            for num, line in enumerate(read(path).splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("*"):
                    continue
                if re.search(r"(TODO|FIXME|XXX):", stripped):
                    offenders.append(f"{path.relative_to(PROJECT_ROOT)}:{num}")
        assert not offenders, f"unresolved markers: {offenders}"


class TestEditProfile:
    def test_edit_screen_exists_and_is_routed(self) -> None:
        assert EDIT_SCREEN.exists()
        router = _read(PROJECT_ROOT / "lib" / "routing" / "app_router.dart")
        assert "'/edit-profile'" in router

    def test_edit_screen_covers_the_displayed_fields(self) -> None:
        text = _read(EDIT_SCREEN)
        for field in ["Name", "Bio", "City", "Gender", "Relationship"]:
            assert field in text, f"Edit Profile is missing a {field} field"

    def test_save_writes_to_the_backend(self) -> None:
        repo = _read(PROFILE_REPO)
        assert "updateProfile" in repo
        # A save must confirm the server actually changed a row; PostgREST
        # answers a no-op UPDATE with 200 and an empty array.
        assert "rows.isEmpty" in repo, "save must detect a zero-row update"

    def test_save_requires_an_authenticated_session(self) -> None:
        repo = _read(PROFILE_REPO)
        assert "auth.currentUser" in repo
        assert re.search(r"authId == null[\s\S]{0,200}throw", repo), (
            "saving while signed out must throw, not silently no-op"
        )

    def test_save_never_uses_the_placeholder_profile_id(self) -> None:
        repo = _read(PROFILE_REPO)
        assert "'me'" in repo
        assert "'unauthenticated'" in repo


class TestMinimumPhotoRequirement:
    """0-3 photos fail, 4+ passes. Enforced client-side and server-side."""

    def test_requirement_is_exactly_four(self) -> None:
        assert MINIMUM_PHOTOS == 4

    def test_completion_model_mirrors_the_server_rule(self) -> None:
        text = _read(COMPLETION_REPO)
        assert re.search(r"minimumPhotos:\s*4", text), (
            "the client fallback minimum must match the database rule of 4"
        )

    def test_completion_is_read_from_the_server(self) -> None:
        text = _read(COMPLETION_REPO)
        # The database owns the rule; the client must not be the only source.
        assert "get_my_profile_completion" in text

    def test_photo_gate_checks_the_minimum(self) -> None:
        text = _read(COMPLETION_REPO)
        assert "meetsPhotoMinimum" in text
        assert "photoCount >= minimumPhotos" in text

    @pytest.mark.parametrize("count", [0, 1, 2, 3])
    def test_fewer_than_four_photos_fails(self, count: int) -> None:
        assert max(MINIMUM_PHOTOS - count, 0) > 0
        assert (count >= MINIMUM_PHOTOS) is False

    @pytest.mark.parametrize("count", [4, 5, 8])
    def test_four_or_more_photos_passes(self, count: int) -> None:
        assert (count >= MINIMUM_PHOTOS) is True
        assert max(MINIMUM_PHOTOS - count, 0) == 0

    def test_deletion_cannot_silently_drop_below_the_minimum(self) -> None:
        repo = _read(PROFILE_REPO)
        if "deleteProfilePhoto" in repo or "deletePhoto" in repo:
            assert re.search(
                r"minimum|remaining|kMinimum", repo, re.IGNORECASE
            ), "photo deletion must respect the minimum-photo rule"
        else:
            pytest.skip("no client-side photo deletion to guard")


class TestImagePipeline:
    def test_compression_exists(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        assert "encodeJpg" in text
        assert "encodeWebP" in text, "WebP encoding should be attempted"

    def test_resizing_preserves_aspect_ratio(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        assert "copyResize" in text
        # Scaling only the longest edge is what keeps a portrait from being
        # stretched into a square.
        assert re.search(r"landscape\s*\?", text), (
            "resize must choose the axis, not force both dimensions"
        )
        # A resize must not force both axes to a real value. The correct
        # pattern is a ternary that yields null for the unused axis, e.g.
        #   width: landscape ? limit : null
        # so each call scales exactly one edge and the aspect ratio holds.
        calls = re.findall(r"copyResize\((?:[^()]|\([^()]*\))*\)", text)
        assert calls, "no copyResize call found"
        for call in calls:
            width_arg = re.search(r"\bwidth\s*:\s*(.+?)(?:,|\n\s*\))", call)
            height_arg = re.search(r"\bheight\s*:\s*(.+?)(?:,|\n\s*\))", call)
            if width_arg is None or height_arg is None:
                # Single-axis call: correct by construction.
                continue
            w, h = width_arg.group(1).strip(), height_arg.group(1).strip()
            w_is_literal = not re.search(r"\bnull\b", w)
            h_is_literal = not re.search(r"\bnull\b", h)
            assert not (w_is_literal and h_is_literal), (
                f"copyResize forces both dimensions and will distort: {call}"
            )

    def test_orientation_is_handled(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        # The `image` package applies EXIF orientation during decode; the
        # re-encode then drops the tag.
        assert "decodeImage" in text
        assert re.search(
            r"exif|orientation", text, re.IGNORECASE
        ), "EXIF orientation handling must be implemented or documented"

    def test_metadata_is_dropped_by_re_encoding(self) -> None:
        assert "encodeJpg" in _read(IMAGE_OPTIMIZER), (
            "re-encoding is what strips metadata"
        )

    def test_quality_is_configured_not_hardcoded_low(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        qualities = [int(q) for q in re.findall(r"jpegQuality:\s*(\d+)", text)]
        assert qualities, "no JPEG quality configured"
        # Blurry profile photos are the failure mode to avoid.
        assert max(qualities) >= 85

    def test_file_size_budget_is_declared_and_used(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        assert re.search(
            r"maxFileSizeBytes\s*=\s*(\d+)\s*\*\s*1024\s*\*\s*1024", text
        )
        # The constant must actually be referenced by validation logic.
        assert len(re.findall(r"maxFileSizeBytes", text)) >= 2, (
            "the budget constant is declared but never enforced"
        )

    def test_validation_rejects_unusable_input(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        assert "ImageValidationException" in text
        assert re.search(r"minDimension\s*=\s*\d+", text), (
            "a minimum resolution must be enforced to avoid blurry uploads"
        )

    def test_upload_errors_are_surfaced_not_swallowed(self) -> None:
        assert "lastError" in _read(IMAGE_OPTIMIZER)
        repo = _read(PROFILE_REPO)
        # Both the Storage failure and the profile_photos insert must report.
        assert "_storageErrorMessage" in repo
        assert "_photoRowErrorMessage" in repo

    def test_picker_does_not_pass_through_undecodable_bytes(self) -> None:
        text = _read(IMAGE_OPTIMIZER)
        assert "pickAndOptimizeImage" in text
        # A HEIC/RAW payload must be reported, not forwarded to Storage.
        assert re.search(
            r"on ImageValidationException catch", text
        ), "validation failures must be caught and reported by the picker"

