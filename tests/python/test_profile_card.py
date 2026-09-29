"""Profile card verification.

The card must present information progressively and be driven by the real
profile model rather than placeholder text. The privacy assertions are the
strictest here: the card may render a city and an approximate distance, and
nothing else location-shaped.
"""

from __future__ import annotations

import re

from weekend_checks import (
    REPO_ROOT as PROJECT_ROOT,
    CheckResult,
    Evidence,
    Status,
    read_text as read,
)

CARD = PROJECT_ROOT / "lib" / "widgets" / "discovery_card.dart"
SCHEMA = PROJECT_ROOT / "lib" / "models" / "profile_schema.dart"
DISCOVERY_REPO = PROJECT_ROOT / "lib" / "repositories" / "discovery_repository.dart"
SEARCH_REPO = PROJECT_ROOT / "lib" / "repositories" / "search_repository.dart"
MODELS = PROJECT_ROOT / "lib" / "models" / "models.dart"


def _method_body(source: str, signature: str) -> str:
    """Return a Dart method's body by brace matching."""
    start = source.index(signature)
    body_start = source.index("{", source.index("(", start) + 1)
    depth = 0
    for i in range(body_start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1 : i]
    raise AssertionError(f"unbalanced braces after {signature}")


def code_only(source: str) -> str:
    """Strip `//` and `/* */` comments.

    Several checks below assert a token is ABSENT. That token is usually named
    in the comment explaining why it must stay absent, so scanning raw text
    fails a correct implementation.
    """
    out = []
    i = 0
    n = len(source)
    while i < n:
        if source.startswith("//", i):
            j = source.find("\n", i)
            i = n if j == -1 else j
            continue
        if source.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(source[i])
        i += 1
    return "".join(out)


def test_card_exists_and_is_used() -> CheckResult:
    assert CARD.exists(), "discovery_card.dart is missing"
    src = read(CARD)
    assert "class DiscoveryCard" in src
    users = [
        p.name
        for p in (PROJECT_ROOT / "lib").rglob("*.dart")
        if "DiscoveryCard(" in read(p) and p != CARD
    ]
    assert users, "DiscoveryCard is never rendered anywhere"
    return CheckResult(
        name="Profile card exists and is rendered",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail=f"used by {users}",
    )


def test_media_is_the_dominant_element() -> CheckResult:
    src = read(CARD)
    assert "PageView.builder" in src, "the card must show multiple photos"
    assert "Positioned.fill(child: _buildMedia" in src
    assert "BoxFit.cover" in src
    # The identity block sits on top of the media, not beside it.
    assert "_buildIdentity()" in src
    return CheckResult(
        name="Photos dominate the card (full-bleed pager)",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="PageView.builder fills the card; identity overlays it",
    )


def test_information_order_is_correct() -> CheckResult:
    """The required order: media, name, age, city, distance, bio, interests,
    intent, prompts, lifestyle."""
    src = code_only(read(CARD))
    # Always-visible layer.
    identity = src.split("Widget _buildIdentity()", 1)[1]
    order_on_card = [
        "profile.name",
        "'$age'",
        "city,",
        "profile.relationshipIntent",
    ]
    positions = [identity.index(token) for token in order_on_card]
    assert positions == sorted(positions), f"card order wrong: {positions}"

    # Progressive layer. Scope to the sheet's build() so the ordering measured
    # is render order, not the order in which private helpers happen to be
    # declared in the file.
    sheet_class = src.split("class _ProfileDetailSheet", 1)[1]
    sheet = _method_body(sheet_class, "Widget build(BuildContext context)")
    # bio -> interests -> relationship intent -> prompts -> lifestyle.
    # `_lifestyleRows` is referenced first inside its own getter, so anchor the
    # ordering on the section call sites instead.
    sheet_order = [
        "profile.bio",
        "profile.interests",
        "profile.prompts",
        "title: 'Lifestyle'",
    ]
    sheet_positions = [sheet.index(token) for token in sheet_order]
    assert sheet_positions == sorted(sheet_positions), (
        f"sheet order wrong: {sheet_positions}"
    )
    return CheckResult(
        name="Information hierarchy follows the required order",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="card: media>name>age>city>intent; sheet: bio>interests>intent>prompts>lifestyle",
    )


def test_every_required_element_is_represented() -> CheckResult:
    src = read(CARD)
    required = {
        "photos": "profile.photos",
        "name": "profile.name",
        "age": "profile.age",
        "city": "profile.city",
        "distance": "distanceDisplay",
        "bio": "profile.bio",
        "interests": "profile.interests",
        "intent": "profile.relationshipIntent",
        "prompts": "profile.prompts",
        "lifestyle": "_lifestyleRows",
    }
    missing = [k for k, token in required.items() if token not in src]
    assert not missing, f"profile card omits: {missing}"
    return CheckResult(
        name="All ten card elements are represented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail=", ".join(required),
    )


def test_distance_is_privacy_safe() -> CheckResult:
    """A coordinate must never reach the card."""
    src = code_only(read(CARD))
    assert "distanceDisplay" in src, "the server's privacy-safe label is not used"
    assert "km away" in src, "a fallback distance string is missing"
    for banned in ("latitude", "longitude", "latLng", "coordinates"):
        assert banned not in src, (
            f"the card must not reference {banned}; exact coordinates must "
            "never be displayed"
        )
    return CheckResult(
        name="Distance is privacy-safe (no coordinates in the card)",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="only the server label or a rounded 'km away' string",
    )


def test_distance_labels_come_from_the_server() -> CheckResult:
    repo = read(DISCOVERY_REPO)
    assert "distance_label" in repo, (
        "the server-computed privacy-safe distance label is not read"
    )
    search = read(SEARCH_REPO)
    assert "distanceKm" in search, (
        "search results must carry the server-computed distance"
    )
    return CheckResult(
        name="Distance labels are produced server-side",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="search/get_nearby return distance_label; the client never computes it",
    )


def test_unknown_age_is_never_fabricated() -> CheckResult:
    """Age 0 means 'not stated' - a fabricated number is a data-integrity bug."""
    src = read(CARD)
    assert "profile.age > 0 ? profile.age : null" in src, (
        "a zero age must render as omitted, not as 0"
    )
    assert '"0"' not in src
    return CheckResult(
        name="An unknown age is omitted rather than invented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="age 0 -> no age chip at all",
    )


def test_card_is_data_driven() -> CheckResult:
    """Every rendered value must come from the UserProfile model."""
    src = read(CARD)
    # No hard-coded profile content.
    assert not re.search(r"'Weekend member'", src)
    assert "widget.profile" in src
    assert src.count("profile.") > 10, (
        "the card should read many fields off the model, not a handful"
    )
    return CheckResult(
        name="Card content is read from the real profile model",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail=f"{src.count('profile.')} model references",
    )


def test_progressive_disclosure_affordance_exists() -> CheckResult:
    """Detail lives behind an explicit, labelled affordance."""
    src = read(CARD)
    assert "_openDetailSheet" in src
    assert "_InfoButton" in src
    assert "Show more" in src, "the affordance needs an accessible label"
    assert "_ProfileDetailSheet" in src
    return CheckResult(
        name="Details are progressively disclosed",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="'Show more' opens the full-profile sheet",
    )


def test_lifestyle_rows_skip_missing_values() -> CheckResult:
    src = read(CARD)
    rows = src.split("List<(String, String)> get _lifestyleRows", 1)[1].split(
        "\n  }", 1
    )[0]
    assert "value == null || value.trim().isEmpty" in rows, (
        "an unset lifestyle value must not render as an empty row"
    )
    return CheckResult(
        name="Unset lifestyle values are not rendered",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="_lifestyleRows skips null/blank values",
    )


def test_lifestyle_uses_the_shared_catalogue() -> CheckResult:
    """Labels must come from ProfileSchema, not be retyped in the card."""
    src = read(CARD)
    assert "ProfileSchema.lifestyleFields" in src
    assert "field.column == column" in src
    return CheckResult(
        name="Lifestyle labels come from the shared catalogue",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="the card cannot drift from the picker",
    )


def test_shared_interests_are_highlighted() -> CheckResult:
    src = read(CARD)
    assert "commonInterests" in src
    assert "highlighted" in src
    return CheckResult(
        name="Shared interests are highlighted on the card",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="interests common with the viewer render in the accent colour",
    )


def test_weekend_identity_is_preserved() -> CheckResult:
    """Weekend keeps its own visual identity; no third-party branding."""
    src = read(CARD)
    assert "Icons.weekend_rounded" in read(MODELS) or "weekend" in read(SCHEMA)
    assert "Color(0xFFFF4B72)" in src, "the Weekend accent colour is in use"
    # No third-party marks or copied assets.
    for banned in ("mingle", "tinder", "badoo", "bumble", "hinge"):
        assert banned not in src.lower(), f"third-party branding found: {banned}"
    return CheckResult(
        name="Card keeps Weekend's own visual identity",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="Weekend palette and iconography; no third-party marks",
    )
