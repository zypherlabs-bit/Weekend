import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/discovery_preferences.dart';

/// Reference implementation of the server's `search_profiles` WHERE clause.
///
/// This mirrors migration 020 line-for-line. It exists so the AND semantics
/// are executable and reviewable: a candidate is eligible only when EVERY
/// supplied criterion is true. There is deliberately no scoring branch and
/// no percentage threshold anywhere in this file.
class Candidate {
  final String id;
  final String gender;
  final int? age;
  final double distanceKm;
  final String city;
  final String relationshipIntent;
  final List<String> interests;
  final List<String> languages;
  final Map<String, String> lifestyle;
  final bool isActive;
  final bool isDeleted;
  final bool isBlocked;
  final bool hasMinimumPhotos;

  const Candidate({
    required this.id,
    required this.gender,
    required this.age,
    required this.distanceKm,
    required this.city,
    required this.relationshipIntent,
    this.interests = const [],
    this.languages = const [],
    this.lifestyle = const {},
    this.isActive = true,
    this.isDeleted = false,
    this.isBlocked = false,
    this.hasMinimumPhotos = true,
  });
}

/// Eligibility: `all(...)` over the supplied hard criteria. Never a
/// percentage.
bool isEligible(Candidate c, DiscoveryPreferences p) {
  final checks = <bool>[];

  if (p.genders.isNotEmpty) {
    checks.add(c.gender.toLowerCase() == p.genders.first.toLowerCase());
  }
  if (p.ageMin != null || p.ageMax != null) {
    // An unknown age can never be proven to satisfy the range.
    checks.add(
      c.age != null &&
          c.age! >= (p.ageMin ?? 0) &&
          c.age! <= (p.ageMax ?? 200),
    );
  }
  if (p.maxDistanceKm != null) {
    checks.add(c.distanceKm <= p.maxDistanceKm!);
  }
  if (p.city != null && p.city!.isNotEmpty) {
    checks.add(c.city.toLowerCase() == p.city!.toLowerCase());
  }
  if (p.relationshipIntents.isNotEmpty) {
    checks.add(
      p.relationshipIntents.any(
        (i) => i.toLowerCase() == c.relationshipIntent.toLowerCase(),
      ),
    );
  }
  if (p.interests.isNotEmpty) {
    // ALL requested interests must be present.
    checks.add(
      p.interests.every(
        (want) => c.interests.any((have) => have.toLowerCase() == want.toLowerCase()),
      ),
    );
  }
  if (p.languages.isNotEmpty) {
    checks.add(
      p.languages.every(
        (want) => c.languages.any((have) => have.toLowerCase() == want.toLowerCase()),
      ),
    );
  }
  if (p.lifestyle.isNotEmpty) {
    for (final entry in p.lifestyle.entries) {
      if (entry.value.isEmpty) continue;
      checks.add(c.lifestyle[entry.key] == entry.value);
    }
  }

  // Always-on hard filters.
  checks.add(c.isActive);
  checks.add(!c.isDeleted);
  checks.add(!c.isBlocked);
  checks.add(c.hasMinimumPhotos);

  return checks.every((ok) => ok);
}

List<String> idsOf(List<Candidate> all, DiscoveryPreferences p) =>
    all.where((c) => isEligible(c, p)).map((c) => c.id).toList();

void main() {
  // The scenario from the specification.
  final profiles = <Candidate>[
    const Candidate(
      id: 'A',
      gender: 'Woman',
      age: 28,
      distanceKm: 12,
      city: 'Pune',
      relationshipIntent: 'Long-term relationship',
    ),
    const Candidate(
      id: 'B',
      gender: 'Woman',
      age: 35, // too old
      distanceKm: 12,
      city: 'Pune',
      relationshipIntent: 'Long-term relationship',
    ),
    const Candidate(
      id: 'C',
      gender: 'Man', // wrong gender
      age: 28,
      distanceKm: 10,
      city: 'Pune',
      relationshipIntent: 'Long-term relationship',
    ),
    const Candidate(
      id: 'D',
      gender: 'Woman',
      age: 29,
      distanceKm: 30,
      city: 'Mumbai', // wrong city
      relationshipIntent: 'Long-term relationship',
    ),
  ];

  const preference = DiscoveryPreferences(
    genders: ['Woman'],
    ageMin: 25,
    ageMax: 32,
    maxDistanceKm: 50,
    city: 'Pune',
    relationshipIntents: ['Long-term relationship'],
  );

  group('Preferred Match - the specification scenario', () {
    test('returns only the profile satisfying every hard criterion', () {
      expect(idsOf(profiles, preference), ['A']);
    });

    test('each excluded profile fails for the expected reason', () {
      expect(isEligible(profiles[1], preference), isFalse, reason: 'B is 35');
      expect(isEligible(profiles[2], preference), isFalse, reason: 'C is a man');
      expect(isEligible(profiles[3], preference), isFalse, reason: 'D is in Mumbai');
    });
  });

  group('Hard-filter combinations use AND semantics', () {
    test('gender + age', () {
      const p = DiscoveryPreferences(genders: ['Woman'], ageMin: 25, ageMax: 30);
      // A (28, Pune) and D (29, Mumbai) are both women in range. B is 35 and
      // C is a man, so only the two dimension-specific exclusions apply.
      expect(idsOf(profiles, p), ['A', 'D']);
    });

    test('gender + age + distance', () {
      const p = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 30,
        maxDistanceKm: 11,
      );
      // A is 12 km away, so the tighter radius excludes it too.
      expect(idsOf(profiles, p), isEmpty);
    });

    test('gender + age + city + relationship intent', () {
      const p = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        city: 'Pune',
        relationshipIntents: ['Long-term relationship'],
      );
      expect(idsOf(profiles, p), ['A']);
    });

    test('a contradicting relationship intent returns nothing', () {
      const p = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        relationshipIntents: ['Dating'],
      );
      expect(idsOf(profiles, p), isEmpty);
    });
  });

  group('100% match - no partial credit', () {
    test('a profile matching 4 of 5 criteria is still excluded', () {
      const strict = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        maxDistanceKm: 20,
        city: 'Pune',
        relationshipIntents: ['Long-term relationship'],
      );
      // A satisfies gender, age, city and intent, but a 5 km radius leaves
      // it out: four out of five is not enough.
      const tight = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        maxDistanceKm: 5,
        city: 'Pune',
        relationshipIntents: ['Long-term relationship'],
      );
      expect(isEligible(profiles.first, strict), isTrue);
      expect(isEligible(profiles.first, tight), isFalse);
    });

    test('an unknown age never satisfies a requested range', () {
      const unknownAge = Candidate(
        id: 'U',
        gender: 'Woman',
        age: null,
        distanceKm: 1,
        city: 'Pune',
        relationshipIntent: 'Dating',
      );
      const p = DiscoveryPreferences(ageMin: 25, ageMax: 32);
      expect(isEligible(unknownAge, p), isFalse);
    });

    test('an unset dimension does not filter', () {
      const p = DiscoveryPreferences(genders: ['Woman']);
      // No age filter set, so B (35) is not excluded on age.
      expect(idsOf(profiles, p), containsAll(<String>['A', 'B']));
    });
  });

  group('Lifecycle and safety filters are always applied', () {
    test('inactive, deleted, blocked and photo-deficient are hidden', () {
      const base = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        city: 'Pune',
        relationshipIntents: ['Long-term relationship'],
      );
      expect(isEligible(profiles.first, base), isTrue);

      const hidden = [
        Candidate(
          id: 'X',
          gender: 'Woman',
          age: 28,
          distanceKm: 5,
          city: 'Pune',
          relationshipIntent: 'Long-term relationship',
          isActive: false,
        ),
        Candidate(
          id: 'Y',
          gender: 'Woman',
          age: 28,
          distanceKm: 5,
          city: 'Pune',
          relationshipIntent: 'Long-term relationship',
          isDeleted: true,
        ),
        Candidate(
          id: 'Z',
          gender: 'Woman',
          age: 28,
          distanceKm: 5,
          city: 'Pune',
          relationshipIntent: 'Long-term relationship',
          isBlocked: true,
        ),
        Candidate(
          id: 'W',
          gender: 'Woman',
          age: 28,
          distanceKm: 5,
          city: 'Pune',
          relationshipIntent: 'Long-term relationship',
          hasMinimumPhotos: false,
        ),
      ];

      for (final c in hidden) {
        expect(isEligible(c, base), isFalse, reason: '${c.id} must be hidden');
      }
    });
  });

  group('Interests and languages require ALL selected values', () {
    const rich = <Candidate>[
      Candidate(
        id: 'both',
        gender: 'Woman',
        age: 28,
        distanceKm: 1,
        city: 'Pune',
        relationshipIntent: 'Dating',
        interests: ['Hiking', 'Jazz'],
        languages: ['English', 'Hindi'],
      ),
      Candidate(
        id: 'one',
        gender: 'Woman',
        age: 28,
        distanceKm: 1,
        city: 'Pune',
        relationshipIntent: 'Dating',
        interests: ['Hiking'],
        languages: ['English'],
      ),
    ];

    test('a candidate needs every requested interest', () {
      const p = DiscoveryPreferences(interests: ['Hiking', 'Jazz']);
      expect(idsOf(rich, p), ['both']);
    });

    test('a candidate needs every requested language', () {
      const p = DiscoveryPreferences(languages: ['English', 'Hindi']);
      expect(idsOf(rich, p), ['both']);
    });
  });

  group('Lifestyle matches exactly and ignores cleared controls', () {
    const c = Candidate(
      id: 'L',
      gender: 'Woman',
      age: 28,
      distanceKm: 1,
      city: 'Pune',
      relationshipIntent: 'Dating',
      lifestyle: {'smoking': 'Never', 'pets': 'Dog'},
    );

    test('a matching lifestyle value is eligible', () {
      const p = DiscoveryPreferences(lifestyle: {'smoking': 'Never'});
      expect(isEligible(c, p), isTrue);
    });

    test('a contradicting lifestyle value is excluded', () {
      const p = DiscoveryPreferences(lifestyle: {'smoking': 'Often'});
      expect(isEligible(c, p), isFalse);
    });

    test('an empty lifestyle value is ignored, not a wildcard', () {
      const p = DiscoveryPreferences(lifestyle: {'smoking': '', 'pets': ''});
      expect(p.normalized().lifestyle, isEmpty);
      expect(isEligible(c, p), isTrue);
    });
  });
}
