import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';

/// Unit tests for [SearchFilters].
///
/// These assert the CLIENT contract only. That every hard filter is actually
/// enforced is a database property, verified by:
///   * `tests/python/test_filter_logic.py` (an executable AND-semantics
///     reference plus a check that the SQL expresses the same rules), and
///   * a live query against the deployed `search_profiles` function.
void main() {
  group('SearchFilters defaults', () {
    test('an unfiltered search reports no active filters', () {
      const filters = SearchFilters();
      expect(filters.hasActiveFilters, isFalse);
      expect(filters.activeFilterCount, 0);
    });

    test('a bare distance radius is not counted as a filter', () {
      // The radius is discovery context, not a narrowing choice, so it must
      // not make the UI claim the user filtered anything.
      const filters = SearchFilters(maxDistanceKm: 100);
      expect(filters.hasActiveFilters, isFalse);
    });
  });

  group('SearchFilters hasActiveFilters', () {
    test('detects each narrowing dimension', () {
      expect(const SearchFilters(genders: ['Woman']).hasActiveFilters, isTrue);
      expect(const SearchFilters(interestedIn: ['Man']).hasActiveFilters, isTrue);
      expect(
        const SearchFilters(ageMin: 25, ageMax: 32).hasActiveFilters,
        isTrue,
      );
      expect(
        const SearchFilters(relationshipIntents: ['Long-term relationship'])
            .hasActiveFilters,
        isTrue,
      );
      expect(const SearchFilters(cities: ['Pune']).hasActiveFilters, isTrue);
      expect(const SearchFilters(interests: ['Travel']).hasActiveFilters, isTrue);
      expect(const SearchFilters(languages: ['English']).hasActiveFilters, isTrue);
      expect(const SearchFilters(smoking: 'Never').hasActiveFilters, isTrue);
      expect(const SearchFilters(drinking: 'Never').hasActiveFilters, isTrue);
      expect(const SearchFilters(exercise: 'Often').hasActiveFilters, isTrue);
      expect(const SearchFilters(children: 'No').hasActiveFilters, isTrue);
      expect(const SearchFilters(pets: 'Dog').hasActiveFilters, isTrue);
    });

    test('an age bound on only one side still counts', () {
      expect(const SearchFilters(ageMin: 30).hasActiveFilters, isTrue);
      expect(const SearchFilters(ageMax: 30).hasActiveFilters, isTrue);
    });

    test('counts every active dimension', () {
      const filters = SearchFilters(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        cities: ['Pune'],
        smoking: 'Never',
      );
      expect(filters.activeFilterCount, 4);
    });

    test('includeDealt is a behaviour toggle, not a narrowing filter', () {
      expect(const SearchFilters(includeDealt: true).hasActiveFilters, isFalse);
    });
  });

  group('SearchFilters cleared()', () {
    test('resets filters but keeps the radius and origin', () {
      const filters = SearchFilters(
        maxDistanceKm: 25,
        searchLat: 18.52,
        searchLon: 73.85,
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        smoking: 'Never',
      );
      final cleared = filters.cleared();
      expect(cleared.maxDistanceKm, 25);
      expect(cleared.searchLat, 18.52);
      expect(cleared.searchLon, 73.85);
      expect(cleared.hasActiveFilters, isFalse);
    });
  });

  group('SearchFilters copyWith', () {
    test('clearAge removes BOTH bounds', () {
      const filters = SearchFilters(ageMin: 25, ageMax: 32);
      final cleared = filters.copyWith(clearAge: true);
      // Leaving a dangling bound behind would produce an impossible range.
      expect(cleared.ageMin, isNull);
      expect(cleared.ageMax, isNull);
    });

    test('setting a new age range replaces the old one', () {
      const filters = SearchFilters(ageMin: 25, ageMax: 32);
      final updated = filters.copyWith(ageMin: 30, ageMax: 40);
      expect(updated.ageMin, 30);
      expect(updated.ageMax, 40);
    });

    test('clearSearchCity nulls the display city', () {
      const filters = SearchFilters(searchCity: 'Pune');
      expect(filters.copyWith(clearSearchCity: true).searchCity, isNull);
    });

    test('each lifestyle clear flag removes only its own value', () {
      const filters = SearchFilters(
        smoking: 'Never',
        drinking: 'Socially',
        exercise: 'Often',
        children: 'No',
        pets: 'Dog',
      );
      final after = filters
          .copyWith(clearSmoking: true)
          .copyWith(clearDrinking: true)
          .copyWith(clearExercise: true)
          .copyWith(clearChildren: true)
          .copyWith(clearPets: true);
      expect(after.smoking, isNull);
      expect(after.drinking, isNull);
      expect(after.exercise, isNull);
      expect(after.children, isNull);
      expect(after.pets, isNull);
    });

    test('an omitted argument leaves the existing value alone', () {
      const filters = SearchFilters(genders: ['Woman'], cities: ['Pune']);
      final same = filters.copyWith(ageMax: 40);
      expect(same.genders, ['Woman']);
      expect(same.cities, ['Pune']);
      expect(same.ageMax, 40);
    });
  });

  group('SearchFilters.toRpcParams', () {
    test('sends every RPC parameter with the p_ prefix', () {
      const filters = SearchFilters(
        maxDistanceKm: 50,
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        smoking: 'Never',
      );
      final params = filters.toRpcParams('user-42', limit: 20, offset: 40);
      expect(params['p_user_id'], 'user-42');
      expect(params['p_limit'], 20);
      expect(params['p_offset'], 40);
      expect(params['p_max_distance_km'], 50);
      expect(params['p_genders'], ['Woman']);
      expect(params['p_age_min'], 25);
      expect(params['p_age_max'], 32);
      expect(params['p_smoking'], 'Never');
    });

    test('sends null (not a sentinel) for unset filters', () {
      final params = const SearchFilters().toRpcParams('user-1');
      // The RPC distinguishes "not filtered" from "filtered to nothing",
      // so the client must not invent a value.
      expect(params['p_smoking'], isNull);
      expect(params['p_age_min'], isNull);
      expect(params['p_search_lat'], isNull);
    });

    test('sends an empty list rather than null for multi-selects', () {
      // The function treats cardinality 0 as "no filter" and guards with
      // `is null or cardinality(...) = 0`, so either is correct; an empty
      // list is the clearer wire representation of "nothing selected".
      final params = const SearchFilters().toRpcParams('user-1');
      expect(params['p_genders'], isEmpty);
      expect(params['p_interests'], isEmpty);
    });
  });

  group('SearchResults', () {
    test('reachedEnd reflects whether the server returned a short page', () {
      const partial = SearchResults(profiles: [], reachedEnd: true);
      const maybeMore = SearchResults(profiles: [], reachedEnd: false);
      // An empty page with reachedEnd=false is the failure signal the
      // repository uses, so the UI shows an error rather than "no matches".
      expect(partial.reachedEnd, isTrue);
      expect(maybeMore.reachedEnd, isFalse);
    });
  });
}
