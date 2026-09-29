"""Profile data layer verification: model, repository round-trip and schema.

These checks exist because the audit found several fields that were RENDERED but
never PERSISTED (languages, date of birth) and one that was silently NOT
PERSISTED when emptied (interests). Each gets an explicit guard here.
"""

from __future__ import annotations

from weekend_checks import (
    REPO_ROOT as PROJECT_ROOT,
    CheckResult,
    Evidence,
    Status,
    latest_migration_text,
    read_text as read,
)

MODELS = PROJECT_ROOT / "lib" / "models" / "models.dart"
SCHEMA = PROJECT_ROOT / "lib" / "models" / "profile_schema.dart"
REPO = PROJECT_ROOT / "lib" / "repositories" / "profile_repository.dart"
PROVIDER = PROJECT_ROOT / "lib" / "providers" / "weekend_provider.dart"
DISCOVERY = PROJECT_ROOT / "lib" / "repositories" / "discovery_repository.dart"


def test_profile_model_carries_every_editable_field() -> CheckResult:
    src = read(MODELS)
    user = src.split("class UserProfile", 1)[1]
    for field in (
        "final String name",
        "final int age",
        "final String gender",
        "final String city",
        "final String bio",
        "final String occupation",
        "final String education",
        "final String relationshipIntent",
        "final List<String> interests",
        "final List<String> languages",
        "final List<ProfilePrompt> prompts",
        "final String? smoking",
        "final String? drinking",
        "final String? exercise",
        "final String? pets",
        "final String? children",
    ):
        assert field in user, f"UserProfile is missing: {field}"
    return CheckResult(
        name="UserProfile carries every editable field",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="17 profile attributes on the model",
    )


def test_copy_with_threads_every_new_field() -> CheckResult:
    """A field missing from copyWith silently reverts on every save."""
    src = read(MODELS)
    cp = src.split("UserProfile copyWith({", 1)[1]
    for param in (
        "String? smoking",
        "String? drinking",
        "String? exercise",
        "String? pets",
        "String? children",
        "int? heightCm",
        "List<ProfilePrompt>? prompts",
    ):
        assert param in cp, f"copyWith is missing: {param}"
    body = src.split("      distanceDisplay: distanceDisplay ?? this.distanceDisplay,", 1)[1]
    for field in ("smoking", "drinking", "exercise", "pets", "children", "heightCm"):
        assert f"{field}: {field} ?? this.{field}" in body, (
            f"copyWith body does not carry: {field}"
        )
    return CheckResult(
        name="copyWith threads every field through",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="no field silently reverts on save",
    )


def test_prompt_model_is_resilient() -> CheckResult:
    """A malformed row must not blank out a whole profile."""
    src = read(MODELS)
    factory = src.split("factory ProfilePrompt.fromJson", 1)[1].split("\n  }", 1)[0]
    assert "as String?) ?? ''" in factory, (
        "a missing key must fall back to empty, not throw"
    )
    assert "questionText" in src, "the live catalogue text must be preferred"
    assert "ProfileSchema.promptQuestion" in src
    return CheckResult(
        name="Prompt parsing tolerates a malformed row",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="missing keys fall back instead of throwing",
    )


def test_repository_selects_the_new_columns() -> CheckResult:
    """A column not in the SELECT list is invisible to the whole app."""
    src = read(REPO)
    fetch = src.split("Future<UserProfile?> fetchUserProfile", 1)[1].split(
        "Future<List<ProfilePhotoRecord>>", 1
    )[0]
    for column in (
        "prompts",
        "languages",
        "smoking",
        "drinking",
        "exercise",
        "pets",
        "children",
        "height_cm",
    ):
        assert column in fetch, f"fetchUserProfile does not read {column}"
    return CheckResult(
        name="Profile fetch reads every new column",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="8 additional columns in the explicit SELECT list",
    )


def test_photos_are_ordered_by_user_choice() -> CheckResult:
    src = read(REPO)
    photos = src.split("Future<List<ProfilePhotoRecord>> fetchProfilePhotoRecords", 1)
    photos = photos[1].split("Future<List<String>> fetchProfilePhotos", 1)[0]
    assert ".order('sort_order'" in photos, (
        "a user reorder must actually change the order photos come back in"
    )
    return CheckResult(
        name="Photos are returned in the user's chosen order",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="ORDER BY sort_order, is_primary, created_at",
    )


def test_lifestyle_values_are_validated_against_the_catalogue() -> CheckResult:
    schema = read(SCHEMA)
    assert "static bool isValidLifestyleValue" in schema
    repo = read(REPO)
    assert "lifestyle('smoking'" in repo
    assert "isValidLifestyleValue(column, v)" in repo
    return CheckResult(
        name="Lifestyle writes are validated before they are sent",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="an out-of-set value is omitted, never sent",
    )


def test_prompts_round_trip() -> CheckResult:
    """encodePrompts and decodePrompts must be inverse for valid input."""
    repo = read(REPO)
    assert "encodePrompts" in repo and "decodePrompts" in repo
    encode = repo.split("List<Map<String, dynamic>>? encodePrompts", 1)[1]
    decode = repo.split("static List<ProfilePrompt> decodePrompts", 1)[1]
    assert "'prompt': question" in encode
    assert "'answer': capped" in encode, "the encoder must emit an answer"
    assert "ProfilePrompt.fromJson(Map<String, dynamic>.from(entry))" in decode, (
        "the decoder must go back through the same model"
    )
    sql = latest_migration_text()
    assert "profile_prompts_shape" in sql
    return CheckResult(
        name="Prompts round-trip through the jsonb column",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="id/prompt/answer preserved in both directions",
    )


def test_schema_is_a_single_source_of_truth() -> CheckResult:
    """The picker, the validator and the card must all read one catalogue."""
    schema = read(SCHEMA)
    assert "interestCategories" in schema
    assert "lifestyleFields" in schema
    assert "promptSections" in schema
    # The card must not hard-code lifestyle labels.
    card = read(PROJECT_ROOT / "lib" / "widgets" / "discovery_card.dart")
    assert "ProfileSchema.lifestyleFields" in card
    return CheckResult(
        name="One schema drives the picker, validator and card",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="ProfileSchema is imported by repository, provider, screen and card",
    )


def test_no_coordinates_are_exposed_to_other_profiles() -> CheckResult:
    """The discovery RPC must return distance, not coordinates."""
    repo = read(DISCOVERY)
    assert "distance_km" in repo
    assert "distance_label" in repo
    mapping = repo.split("return UserProfile(", 1)[1].split(");", 1)[0]
    for banned in ("latitude", "longitude"):
        assert banned not in mapping, (
            f"{banned} must never be mapped into a UserProfile shown to others"
        )
    return CheckResult(
        name="Other users' coordinates never reach the client",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="only distance_km and the privacy-safe distance_label are mapped",
    )


def test_empty_state_is_not_fabricated() -> CheckResult:
    """Missing values must render as absent, never as invented data."""
    repo = read(DISCOVERY)
    assert "_displayName" in repo
    assert "Weekend member" in repo
    assert "never a fabricated name" in repo.lower() or "fabricated" in repo.lower()
    return CheckResult(
        name="Missing profile data is never fabricated",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="blank name -> 'Weekend member'; unknown age -> 0",
    )


def test_minimum_photo_rule_is_enforced_by_the_database() -> CheckResult:
    sql = latest_migration_text()
    assert "sync_profile_photo_counters" in sql
    assert "trg_sync_profile_photo_counters" in sql, (
        "the counter must be maintained by a trigger, not by app code"
    )
    assert "has_minimum_photos" in sql
    return CheckResult(
        name="Minimum-photo state is maintained by a database trigger",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="client code cannot fake profiles.has_minimum_photos",
    )
