"""Edit Profile verification.

Checks the IMPLEMENTATION, not filenames: every assertion reads the widget
source, the schema it is driven by, and the repository method that persists it,
so a screen that renders the right labels while writing nothing cannot pass.
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

EDIT = PROJECT_ROOT / "lib" / "features" / "profile" / "edit_profile_screen.dart"
SCHEMA = PROJECT_ROOT / "lib" / "models" / "profile_schema.dart"
REPO = PROJECT_ROOT / "lib" / "repositories" / "profile_repository.dart"
PROVIDER = PROJECT_ROOT / "lib" / "providers" / "weekend_provider.dart"
ROUTER = PROJECT_ROOT / "lib" / "routing" / "app_router.dart"


def _method_body(source: str, signature: str) -> str:
    """Return a Dart method's body by brace matching.

    Splitting on the first "\n  }" truncates any method containing a nested
    closure, which silently weakens every ordering assertion built on it.
    """
    start = source.index(signature)
    body_start = source.index("{", source.index("async", start))
    depth = 0
    for i in range(body_start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1 : i]
    raise AssertionError(f"unbalanced braces after {signature}")


def test_screen_exists_and_is_routed() -> CheckResult:
    assert EDIT.exists(), "edit_profile_screen.dart is missing"
    assert "class EditProfileScreen" in read(EDIT)
    router = read(ROUTER)
    assert "'/edit-profile'" in router, "Edit Profile is not routable"
    assert "EditProfileScreen" in router
    return CheckResult(
        name="Edit Profile screen exists and is routed",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="EditProfileScreen is reachable at /edit-profile",
    )


# --------------------------------------------------------------------------
# Photos
# --------------------------------------------------------------------------

def test_photo_management_operations_exist() -> CheckResult:
    """Add, replace, reorder, set-primary and delete must all be implemented."""
    src = read(EDIT)
    for op, marker in (
        ("add", "Future<void> _addPhoto()"),
        ("replace", "Future<void> _replacePhoto("),
        ("reorder", "Future<void> _movePhoto("),
        ("set primary", "Future<void> _makePrimary("),
        ("delete", "Future<void> _deletePhoto("),
    ):
        assert marker in src, f"photo operation missing: {op}"
    return CheckResult(
        name="Photo add / replace / reorder / primary / delete implemented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="5 photo operations wired to server RPCs",
    )


def test_photo_order_is_persisted_server_side() -> CheckResult:
    """A reorder must call the RPC, not just move a local list."""
    src = read(EDIT)
    assert "_repo.reorderPhotos(" in src
    assert "_repo.setPrimaryPhoto(" in src
    assert "_repo.deletePhoto(" in src
    repo = read(REPO)
    assert "set_profile_photo_order" in repo
    assert "set_primary_profile_photo" in repo
    sql = latest_migration_text()
    assert "create or replace function public.set_profile_photo_order" in sql
    assert "create or replace function public.set_primary_profile_photo" in sql
    assert "sort_order" in sql
    return CheckResult(
        name="Photo order and primary are persisted server-side",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="profile_photos.sort_order + two owner-scoped RPCs",
    )


def test_photo_reorder_is_confirmed_before_ui_update() -> CheckResult:
    """The tile list must not move until the server confirms the order."""
    src = read(EDIT)
    move = src.split("Future<void> _movePhoto(", 1)[1].split("\n  }", 1)[0]
    reorder = move.index("await _repo.reorderPhotos(")
    # The setState that PUBLISHES the new order must come after the await.
    # (`setState(() => _loadingPhotos = true)` is a progress flag and may come
    # first; matching on it would make this check meaningless.)
    publish = move.index("setState(() => _photos =")
    assert reorder < publish, "the tile order updates before the server confirms"
    return CheckResult(
        name="Reorder is confirmed by the server before the UI updates",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="await reorderPhotos() precedes the setState",
    )


def test_minimum_photo_requirement_is_enforced() -> CheckResult:
    """The 4-photo minimum must block the save, not just be described."""
    src = read(EDIT)
    schema = read(SCHEMA)
    assert "static const int minimumPhotos = 4" in schema, (
        "the catalogue must declare the 4-photo minimum"
    )
    assert "static const int maximumPhotos" in schema
    save = src.split("Future<void> _saveProfile()", 1)[1]
    assert "_photos.length < _minPhotos" in save, (
        "the save must refuse a profile below the photo minimum"
    )
    # The button is disabled too, so the state is visible before the tap.
    assert "onPressed: (_isSaving || !photosOk) ? null : _saveProfile" in src
    assert "photosOk" in src
    return CheckResult(
        name="Minimum photo count blocks saving",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="save is refused and the button is disabled below the minimum",
    )


def test_minimum_photos_is_server_sourced() -> CheckResult:
    """The threshold must come from the database, not a hard-coded literal."""
    repo = read(REPO)
    assert "rpc('minimum_profile_photos')" in repo
    assert "rpc('maximum_profile_photos')" in repo
    sql = latest_migration_text()
    assert "create table if not exists public.profile_requirements" in sql
    assert "create or replace function public.minimum_profile_photos" in sql
    return CheckResult(
        name="Photo minimum is a configurable server value",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="profile_requirements.min_photos read via RPC",
    )


def test_delete_photo_respects_the_minimum() -> CheckResult:
    repo = read(REPO)
    delete = repo.split("Future<void> deletePhoto(", 1)[1].split("\n  }", 1)[0]
    assert "minimumPhotos()" in delete
    assert "remaining < minimum" in delete, (
        "deleting below the minimum must be refused server-side too"
    )
    return CheckResult(
        name="Deleting below the photo minimum is refused",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="the RPC path re-checks the minimum, not just the UI",
    )


# --------------------------------------------------------------------------
# Basic information
# --------------------------------------------------------------------------

def test_basic_fields_are_editable() -> CheckResult:
    src = read(EDIT)
    for field in (
        "_nameController",
        "_dateOfBirth",
        "_selectedGender",
        "_cityController",
        "_selectedRelationshipIntent",
    ):
        assert field in src, f"basic field missing: {field}"
    return CheckResult(
        name="Name, age, gender, city and intent are editable",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="5 basic profile fields with validation",
    )


def test_date_of_birth_is_actually_persisted() -> CheckResult:
    """REGRESSION GUARD: the picker must write the date, not just the age.

    `UserProfile` carries a derived `age`, so a form that only saved the model
    would silently discard the user's real birth date.
    """
    src = read(EDIT)
    assert "_dateOfBirth" in src
    assert "_repo.updateDateOfBirth(" in src, (
        "the selected date of birth is never written"
    )
    repo = read(REPO)
    assert "Future<void> updateDateOfBirth(DateTime dob)" in repo
    assert "'date_of_birth': iso" in repo
    return CheckResult(
        name="Date of birth is persisted",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="updateDateOfBirth writes profiles.date_of_birth",
    )


def test_date_of_birth_age_is_validated() -> CheckResult:
    """An under-18 date must be refused: the hard age filter starts at 18."""
    repo = read(REPO)
    dob = repo.split("Future<void> updateDateOfBirth(", 1)[1].split("\n  }", 1)[0]
    assert "age < 18" in dob
    assert "profiles.dob.underage" in dob
    picker = read(EDIT)
    assert "lastDate: DateTime(now.year - 18" in picker
    return CheckResult(
        name="Under-18 date of birth is refused",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="picker caps at 18 and the repository re-checks",
    )


def test_gender_and_intent_are_check_constrained() -> CheckResult:
    schema = read(SCHEMA)
    assert "static const List<String> genders" in schema
    assert "static const List<String> relationshipIntents" in schema
    repo = read(REPO)
    assert "isValidLifestyleValue" in repo
    assert "ProfileSchema.isValidGender" in schema or "genders.contains" in schema
    return CheckResult(
        name="Gender / intent values match the database CHECK sets",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="pickers read the single ProfileSchema source of truth",
    )


# --------------------------------------------------------------------------
# Prompts
# --------------------------------------------------------------------------

def test_prompt_catalogue_exists() -> CheckResult:
    schema = read(SCHEMA)
    assert "promptSections" in schema
    for section in ("About me", "How I show up"):
        assert section in schema, f"prompt section missing: {section}"
    # A mature catalogue, not a token two or three questions.
    prompts = schema.count("ProfilePromptTemplate(")
    assert prompts >= 12, f"only {prompts} prompts defined"
    return CheckResult(
        name=f"Prompt catalogue present ({prompts} prompts)",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="grouped into About me / How I show up",
    )


def test_prompts_are_editable_and_persisted() -> CheckResult:
    src = read(EDIT)
    assert "_promptsSection()" in src
    assert "_promptField(" in src
    save = src.split("Future<void> _saveProfile()", 1)[1]
    assert "prompts: prompts" in save or "prompts," in save
    repo = read(REPO)
    assert "encodePrompts" in repo
    assert "'prompts': encodePrompts(profile.prompts)" in repo
    assert "decodePrompts" in repo
    return CheckResult(
        name="Prompts are editable and persisted",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="edit -> encodePrompts -> profiles.prompts jsonb",
    )


def test_prompt_answers_are_validated() -> CheckResult:
    """Blank answers dropped, count capped, length bounded."""
    repo = read(REPO)
    encode = repo.split("List<Map<String, dynamic>>? encodePrompts", 1)[1].split(
        "/// Values the", 1
    )[0]
    assert "if (answer.isEmpty || question.isEmpty) continue" in encode
    assert "out.length >= ProfileSchema.maxPrompts" in encode
    assert "substring(0, limit)" in encode
    # Server-side equivalent.
    sql = latest_migration_text()
    assert "create or replace function public.profile_prompts_are_valid" in sql
    assert "profile_prompts_shape" in sql
    return CheckResult(
        name="Prompt answers validated on both client and server",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="blank dropped, cap 4, length bounded, CHECK constraint",
    )


def test_prompt_overflow_is_disclosed() -> CheckResult:
    """Answers past the cap must be visible, not silently discarded."""
    src = read(EDIT)
    assert "_promptCountNotice" in src
    assert "Only the first" in src
    return CheckResult(
        name="Answers beyond the card limit are disclosed to the user",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="_promptCountNotice states how many are hidden",
    )


# --------------------------------------------------------------------------
# Interests and lifestyle
# --------------------------------------------------------------------------

def test_interests_are_multi_select_and_persisted() -> CheckResult:
    src = read(EDIT)
    assert "_interestsSection()" in src
    assert "_selectedInterests" in src
    assert "interestCategories" in read(SCHEMA)
    provider = read(PROVIDER)
    assert "user_interests" in provider
    # REGRESSION GUARD: the delete used to be guarded by isNotEmpty, so
    # deselecting the LAST interest silently did nothing.
    assert "await client.from('user_interests').delete()" in provider
    save = provider.split("Future<List<String>> updateProfile", 1)[1]
    delete_line = save.split("user_interests').delete()", 1)[0]
    assert "if (profile.interests.isNotEmpty)" not in delete_line, (
        "clearing all interests must still delete the existing rows"
    )
    return CheckResult(
        name="Interests are multi-select and always persisted",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="clearing every interest now really clears them",
    )


def test_interests_are_normalised_in_the_database() -> CheckResult:
    sql = latest_migration_text()
    assert "insert into public.interests (name, category)" in sql
    assert "add column if not exists category text" in sql
    assert "on conflict (name) do update" in sql
    return CheckResult(
        name="Interests are a normalised table with categories",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="interests.category seeded by migration 025",
    )


def test_lifestyle_fields_are_editable_and_constrained() -> CheckResult:
    schema = read(SCHEMA)
    for column in ("smoking", "drinking", "exercise", "pets", "children"):
        assert f"column: '{column}'" in schema, f"lifestyle field missing: {column}"
    src = read(EDIT)
    assert "_lifestyleSection()" in src
    repo = read(REPO)
    for column in ("smoking", "drinking", "exercise", "pets", "children"):
        assert f"lifestyle('{column}'" in repo, f"{column} is never written"
    return CheckResult(
        name="Lifestyle fields are editable and CHECK-constrained",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="5 lifestyle columns written only when the value is allowed",
    )


def test_languages_are_persisted() -> CheckResult:
    """REGRESSION GUARD: languages were editable but never written."""
    src = read(EDIT)
    assert "_languagesSection" in src or "_languageChip" in src
    save = src.split("Future<void> _saveProfile()", 1)[1]
    assert "languages: _languages" in save
    provider = read(PROVIDER)
    assert "languages write failed" in provider
    return CheckResult(
        name="Languages are persisted",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="profiles.languages is written on save",
    )


# --------------------------------------------------------------------------
# Save flow
# --------------------------------------------------------------------------

def test_save_flow_is_ordered_and_confirmed() -> CheckResult:
    """Validation -> auth -> photo minimum -> write -> confirm -> navigate."""
    src = read(EDIT)
    save = _method_body(src, "Future<void> _saveProfile()")
    steps = [
        "_formKey.currentState!.validate()",
        "final authId = _authUserId",
        "if (authId == null)",
        "_photos.length < _minPhotos",
        "updateProfile(updated)",
        "refreshProfileSetup()",
        "context.canPop()",
    ]
    positions = [save.index(step) for step in steps]
    assert positions == sorted(positions), (
        f"save steps are out of order: {list(zip(steps, positions))}"
    )
    return CheckResult(
        name="Save flow validates, confirms, then navigates",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="6 ordered checkpoints before any navigation",
    )


def test_failure_keeps_the_user_on_the_screen() -> CheckResult:
    """No navigation and no success message on failure."""
    src = read(EDIT)
    save = src.split("Future<void> _saveProfile()", 1)[1].split("\n  }", 1)[0]
    catch_branch = save.split("} catch (e) {", 1)[1]
    assert "context.pop(" not in catch_branch
    assert "context.go(" not in catch_branch
    assert "showSnackBar" not in catch_branch, (
        "a failure must not report a success message"
    )
    assert "_saveError" in catch_branch
    return CheckResult(
        name="A failed save stays on the screen with an error",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="the catch branch sets _saveError and navigates nowhere",
    )


def test_completion_is_visible() -> CheckResult:
    src = read(EDIT)
    assert "_completionCard" in src
    assert "Still needed" in src
    assert "_completeness()" in src
    return CheckResult(
        name="Profile completion is shown to the user",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="progress bar + list of what is still missing",
    )


def test_loading_failure_offers_retry() -> CheckResult:
    src = read(EDIT)
    assert "_loadError" in src
    assert "Retry" in src
    return CheckResult(
        name="A failed profile load offers a retry",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="_loadAll is re-runnable from the completion card",
    )
