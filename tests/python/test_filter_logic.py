"""Executable model of the hard-filter rules (RUNTIME verification).

This is a faithful Python reimplementation of the `search_profiles` WHERE
clause, executed against the scenario in the specification to prove the AND
semantics behave as documented. The STATIC half - does the shipped SQL
actually say this? - lives in ``test_search_sql.py``.

Design rule enforced throughout: eligibility is ``all(...)`` over the
supplied criteria. There is deliberately no weighted score, no percentage
and no "close enough" branch.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

import pytest


@dataclass
class Candidate:
    """A profile row as the server would evaluate it."""

    id: str
    gender: str
    age: int | None
    distance_km: float
    city: str
    relationship_intent: str
    interests: list[str] = field(default_factory=list)
    languages: list[str] = field(default_factory=list)
    lifestyle: dict[str, str] = field(default_factory=dict)
    is_active: bool = True
    deleted: bool = False
    blocked: bool = False
    dating_profile_activated: bool = True
    has_name: bool = True


@dataclass
class Preferences:
    """A hard-filter selection. ``None``/empty means "not restricted"."""

    genders: list[str] | None = None
    age_min: int | None = None
    age_max: int | None = None
    max_distance_km: float | None = None
    city: str | None = None
    relationship_intents: list[str] | None = None
    interests: list[str] | None = None
    languages: list[str] | None = None
    lifestyle: dict[str, str] = field(default_factory=dict)


def _present(want: str, have: Iterable[str]) -> bool:
    return want.strip().lower() in {h.strip().lower() for h in have}


def is_eligible(c: Candidate, p: Preferences) -> bool:
    """A candidate is eligible only if EVERY supplied criterion holds."""
    checks: list[bool] = []

    if p.genders:
        # An unknown gender cannot be proven to match the selection.
        checks.append(any(_present(g, [c.gender]) for g in p.genders))

    if p.age_min is not None or p.age_max is not None:
        # An unknown age is NOT treated as in-range.
        checks.append(
            c.age is not None
            and c.age >= (p.age_min if p.age_min is not None else 0)
            and c.age <= (p.age_max if p.age_max is not None else 200)
        )

    if p.max_distance_km is not None:
        checks.append(c.distance_km <= p.max_distance_km)

    if p.city and p.city.strip():
        checks.append(c.city.strip().lower() == p.city.strip().lower())

    if p.relationship_intents:
        checks.append(
            any(
                _present(i, [c.relationship_intent])
                for i in p.relationship_intents
            )
        )

    if p.interests:
        # ALL requested interests must be present, not "some of them".
        checks.append(all(_present(i, c.interests) for i in p.interests))

    if p.languages:
        checks.append(all(_present(lg, c.languages) for lg in p.languages))

    for key, want in (p.lifestyle or {}).items():
        if want == "":
            # A cleared control must not exclude anyone.
            continue
        checks.append(c.lifestyle.get(key) == want)

    # Always-on hard filters.
    checks.append(c.is_active)
    checks.append(not c.deleted)
    checks.append(not c.blocked)
    checks.append(c.dating_profile_activated)
    checks.append(c.has_name)

    return all(checks)


def eligible_ids(profiles: list[Candidate], p: Preferences) -> list[str]:
    return [c.id for c in profiles if is_eligible(c, p)]


# The scenario from the specification.
PROFILES = [
    Candidate("A", "Woman", 28, 12, "Pune", "Long-term relationship"),
    Candidate("B", "Woman", 35, 12, "Pune", "Long-term relationship"),
    Candidate("C", "Man", 28, 10, "Pune", "Long-term relationship"),
    Candidate("D", "Woman", 29, 30, "Mumbai", "Long-term relationship"),
]

SPEC_PREFERENCE = Preferences(
    genders=["Woman"],
    age_min=25,
    age_max=32,
    max_distance_km=50,
    city="Pune",
    relationship_intents=["Long-term relationship"],
)


class TestSpecificationScenario:
    """Female, 25-32, <=50 km, long-term, Pune -> only Profile A."""

    def test_only_profile_a_is_returned(self) -> None:
        assert eligible_ids(PROFILES, SPEC_PREFERENCE) == ["A"]

    def test_b_is_excluded_because_of_age(self) -> None:
        assert not is_eligible(PROFILES[1], SPEC_PREFERENCE)

    def test_c_is_excluded_because_of_gender(self) -> None:
        assert not is_eligible(PROFILES[2], SPEC_PREFERENCE)

    def test_d_is_excluded_because_of_city(self) -> None:
        assert not is_eligible(PROFILES[3], SPEC_PREFERENCE)

    def test_every_excluded_profile_is_absent(self) -> None:
        returned = eligible_ids(PROFILES, SPEC_PREFERENCE)
        for excluded in ("B", "C", "D"):
            assert excluded not in returned


class TestAndSemantics:
    def test_gender_plus_age(self) -> None:
        p = Preferences(genders=["Woman"], age_min=25, age_max=30)
        # A (28, Pune) and D (29, Mumbai) are both women in range. B is 35 and
        # C is a man, so only those two are excluded.
        assert eligible_ids(PROFILES, p) == ["A", "D"]

    def test_gender_plus_age_plus_distance(self) -> None:
        tight = Preferences(
            genders=["Woman"], age_min=25, age_max=30, max_distance_km=11
        )
        # A is 12 km and D is 30 km away, so nothing survives.
        assert eligible_ids(PROFILES, tight) == []

        looser = Preferences(
            genders=["Woman"], age_min=25, age_max=30, max_distance_km=15
        )
        assert eligible_ids(PROFILES, looser) == ["A"]

    def test_gender_plus_age_plus_city_plus_intent(self) -> None:
        p = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=32,
            city="Pune",
            relationship_intents=["Long-term relationship"],
        )
        assert eligible_ids(PROFILES, p) == ["A"]

    def test_gender_plus_age_plus_distance_plus_lifestyle(self) -> None:
        styled = [
            Candidate(
                "L1",
                "Woman",
                28,
                5,
                "Pune",
                "Dating",
                lifestyle={"pets": "Dog"},
            ),
            Candidate(
                "L2",
                "Woman",
                28,
                5,
                "Pune",
                "Dating",
                lifestyle={"pets": "None"},
            ),
        ]
        p = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=30,
            max_distance_km=10,
            lifestyle={"pets": "Dog"},
        )
        assert eligible_ids(styled, p) == ["L1"]

    def test_gender_age_distance_interests_and_intent(self) -> None:
        rich = [
            Candidate(
                "R1",
                "Woman",
                28,
                5,
                "Pune",
                "Long-term relationship",
                interests=["Hiking", "Jazz"],
            ),
            Candidate(
                "R2",
                "Woman",
                28,
                5,
                "Pune",
                "Long-term relationship",
                interests=["Hiking"],
            ),
            Candidate(
                "R3",
                "Woman",
                28,
                5,
                "Pune",
                "Dating",
                interests=["Hiking", "Jazz"],
            ),
        ]
        p = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=30,
            max_distance_km=10,
            relationship_intents=["Long-term relationship"],
            interests=["Hiking", "Jazz"],
        )
        # R2 is missing Jazz; R3 has the wrong intent.
        assert eligible_ids(rich, p) == ["R1"]

    def test_distance_alone(self) -> None:
        # A(12) B(12) C(10) within 25 km; D is 30 km.
        assert eligible_ids(PROFILES, Preferences(max_distance_km=25)) == [
            "A",
            "B",
            "C",
        ]

    def test_city_alone(self) -> None:
        assert eligible_ids(PROFILES, Preferences(city="Pune")) == ["A", "B", "C"]


class TestNoPartialCredit:
    """Required criteria must be 100% satisfied - never a percentage."""

    def test_four_of_five_criteria_is_not_enough(self) -> None:
        loose = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=32,
            max_distance_km=20,
            city="Pune",
            relationship_intents=["Long-term relationship"],
        )
        tight = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=32,
            max_distance_km=5,
            city="Pune",
            relationship_intents=["Long-term relationship"],
        )
        assert is_eligible(PROFILES[0], loose)
        assert not is_eligible(PROFILES[0], tight)

    def test_ninety_percent_match_does_not_pass(self) -> None:
        # Nine of ten criteria satisfied; the tenth (city) is wrong.
        p = Preferences(
            genders=["Woman"],
            age_min=25,
            age_max=32,
            max_distance_km=50,
            city="Mumbai",
            relationship_intents=["Long-term relationship"],
        )
        assert not is_eligible(PROFILES[0], p)

    def test_no_score_or_percentage_gate_in_the_model(self) -> None:
        import re

        source = open(__file__, encoding="utf-8").read()
        # Guard against a future edit reintroducing score-based filtering.
        assert not re.search(r"(score|percent\w*)\s*(>=|>)\s*\d", source, re.I)

    def test_unknown_age_never_satisfies_a_requested_range(self) -> None:
        unknown = Candidate("U", "Woman", None, 1, "Pune", "Dating")
        assert not is_eligible(unknown, Preferences(age_min=25, age_max=32))

    def test_unset_dimension_does_not_filter(self) -> None:
        # No age filter, so B (35) survives a gender-only preference.
        assert eligible_ids(PROFILES, Preferences(genders=["Woman"])) == [
            "A",
            "B",
            "D",
        ]


class TestLifecycleFilters:
    @pytest.mark.parametrize(
        "kwargs",
        [
            {"is_active": False},
            {"deleted": True},
            {"blocked": True},
            {"dating_profile_activated": False},
            {"has_name": False},
        ],
    )
    def test_safety_flags_always_hide_a_profile(self, kwargs: dict) -> None:
        hidden = Candidate("H", "Woman", 28, 1, "Pune", "Dating", **kwargs)
        assert not is_eligible(hidden, Preferences(genders=["Woman"]))

    def test_unrestricted_preference_still_hides_unusable_profiles(self) -> None:
        hidden = Candidate("H", "Woman", 28, 1, "Pune", "Dating", deleted=True)
        assert not is_eligible(hidden, Preferences())


class TestMultiValueCriteria:
    RICH = [
        Candidate(
            "both",
            "Woman",
            28,
            1,
            "Pune",
            "Dating",
            interests=["Hiking", "Jazz"],
            languages=["English", "Hindi"],
        ),
        Candidate(
            "one",
            "Woman",
            28,
            1,
            "Pune",
            "Dating",
            interests=["Hiking"],
            languages=["English"],
        ),
    ]

    def test_all_requested_interests_must_be_present(self) -> None:
        assert eligible_ids(self.RICH, Preferences(interests=["Hiking", "Jazz"])) == [
            "both"
        ]

    def test_all_requested_languages_must_be_present(self) -> None:
        assert eligible_ids(
            self.RICH, Preferences(languages=["English", "Hindi"])
        ) == ["both"]

    def test_lifestyle_must_match_exactly(self) -> None:
        c = Candidate(
            "L", "Woman", 28, 1, "Pune", "Dating", lifestyle={"smoking": "Never"}
        )
        assert is_eligible(c, Preferences(lifestyle={"smoking": "Never"}))
        assert not is_eligible(c, Preferences(lifestyle={"smoking": "Often"}))

    def test_empty_lifestyle_value_is_ignored_not_a_wildcard(self) -> None:
        c = Candidate(
            "L", "Woman", 28, 1, "Pune", "Dating", lifestyle={"smoking": "Never"}
        )
        assert is_eligible(c, Preferences(lifestyle={"smoking": ""}))

    def test_several_lifestyle_keys_are_all_enforced(self) -> None:
        c = Candidate(
            "L",
            "Woman",
            28,
            1,
            "Pune",
            "Dating",
            lifestyle={"smoking": "Never", "pets": "Dog"},
        )
        assert is_eligible(
            c, Preferences(lifestyle={"smoking": "Never", "pets": "Dog"})
        )
        assert not is_eligible(
            c, Preferences(lifestyle={"smoking": "Never", "pets": "Cat"})
        )
