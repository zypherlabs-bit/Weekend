import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/features/qr/about_open_source_screen.dart';
import 'package:weekend/models/discovery_preferences.dart';
import 'package:weekend/repositories/search_repository.dart';

void main() {
  group('QR code destination', () {
    test('points at the official Weekend repository', () {
      expect(
        kWeekendRepositoryUrl,
        'https://github.com/zypherlabs-bit/Weekend',
      );
    });

    test('has no query string, fragment, credentials or tracking params', () {
      final uri = Uri.parse(kWeekendRepositoryUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/zypherlabs-bit/Weekend');
      expect(uri.query, isEmpty);
      expect(uri.fragment, isEmpty);
      expect(uri.userInfo, isEmpty);
    });

    test('encodes no secret, token or user data', () {
      // A QR payload must never carry a credential. The only thing encoded
      // is the public repository URL.
      for (final forbidden in [
        'service_role',
        'eyJ',
        'supabase',
        'token',
        'password',
        'secret',
      ]) {
        expect(
          kWeekendRepositoryUrl.toLowerCase(),
          isNot(contains(forbidden)),
        );
      }
    });
  });

  group('search_profiles RPC parameters', () {
    test('an unset dimension is sent as null, never a sentinel', () {
      const prefs = DiscoveryPreferences(genders: ['Woman']);
      final params = prefs.toRpcParams('viewer-uuid');

      expect(params['p_genders'], ['Woman']);
      expect(params['p_age_min'], isNull);
      expect(params['p_age_max'], isNull);
      expect(params['p_max_distance_km'], isNull);
      expect(params['p_city'], isNull);
      expect(params['p_interests'], isNull);
      expect(params['p_lifestyle'], isNull);
      expect(params['p_user_id'], 'viewer-uuid');
    });

    test('every selected hard filter is transmitted', () {
      const prefs = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        maxDistanceKm: 50,
        city: 'Pune',
        relationshipIntents: ['Long-term relationship'],
        interests: ['Hiking'],
        languages: ['English'],
        lifestyle: {'smoking': 'Never'},
      );
      final params = prefs.toRpcParams('viewer-uuid');

      expect(params['p_genders'], ['Woman']);
      expect(params['p_age_min'], 25);
      expect(params['p_age_max'], 32);
      expect(params['p_max_distance_km'], 50);
      expect(params['p_city'], 'Pune');
      expect(params['p_relationship_intents'], ['Long-term relationship']);
      expect(params['p_interests'], ['Hiking']);
      expect(params['p_languages'], ['English']);
      expect(params['p_lifestyle'], {'smoking': 'Never'});
    });

    test('paging is passed through explicitly', () {
      const prefs = DiscoveryPreferences.unrestricted();
      final params = prefs.toRpcParams('u', page: 3, pageSize: 25);
      expect(params['p_page'], 3);
      expect(params['p_page_size'], 25);
    });
  });


  group('DiscoveryPreferences invariants', () {
    test('normalization orders and clamps the age range', () {
      const prefs = DiscoveryPreferences(ageMin: 40, ageMax: 20);
      final n = prefs.normalized();
      expect(n.ageMin, 20);
      expect(n.ageMax, 40);

      const underage = DiscoveryPreferences(ageMin: 12);
      expect(underage.normalized().ageMin, DiscoveryPreferences.kMinimumAge);
    });

    test('a blank city is treated as no city filter', () {
      const prefs = DiscoveryPreferences(city: '   ');
      expect(prefs.normalized().city, isNull);
      expect(prefs.isCityRestricted, isFalse);
    });

    test('clearCity actually removes the filter', () {
      const prefs = DiscoveryPreferences(city: 'Pune');
      expect(prefs.copyWith(clearCity: true).city, isNull);
    });

    test('activeFilterCount reflects the selections', () {
      const none = DiscoveryPreferences();
      expect(none.activeFilterCount, 0);
      expect(none.hasAnyFilter, isFalse);

      const some = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        city: 'Pune',
      );
      expect(some.activeFilterCount, 3);
      expect(some.hasAnyFilter, isTrue);
    });

    test('the empty state can explain what is constraining results', () {
      const prefs = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        city: 'Pune',
      );
      expect(
        prefs.activeFilterLabels,
        containsAll(['Gender: Woman', 'Age: 25–32', 'City: Pune']),
      );
    });

    test('equality is case-insensitive so a re-query is not triggered', () {
      const a = DiscoveryPreferences(city: 'Pune', genders: ['Woman']);
      const b = DiscoveryPreferences(city: 'pune', genders: ['woman']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('survives a JSON round trip', () {
      const prefs = DiscoveryPreferences(
        genders: ['Woman'],
        ageMin: 25,
        ageMax: 32,
        maxDistanceKm: 50,
        city: 'Pune',
        relationshipIntents: ['Dating'],
        interests: ['Hiking'],
        languages: ['English'],
        lifestyle: {'pets': 'Dog'},
        locationMode: LocationMode.travel,
      );
      expect(DiscoveryPreferences.fromJson(prefs.toJson()), equals(prefs));
    });
  });

  group('Minimum 4 photos', () {
    test('0, 1, 2 and 3 photos all fail the requirement', () {
      for (final count in [0, 1, 2, 3]) {
        final completion = ProfileCompletion(
          profileExists: true,
          photoCount: count,
          minimumPhotos: 4,
          hasName: true,
          hasBirthdate: true,
          hasCity: true,
          hasBio: true,
        );
        expect(completion.meetsPhotoMinimum, isFalse, reason: '$count photos');
        expect(completion.isComplete, isFalse, reason: '$count photos');
        expect(completion.photosRemaining, 4 - count);
      }
    });

    test('exactly 4 photos passes', () {
      final completion = ProfileCompletion(
        profileExists: true,
        photoCount: 4,
        minimumPhotos: 4,
        hasName: true,
        hasBirthdate: true,
        hasCity: true,
        hasBio: true,
      );
      expect(completion.meetsPhotoMinimum, isTrue);
      expect(completion.photosRemaining, 0);
      expect(completion.isComplete, isTrue);
    });

    test('more than 4 photos also passes', () {
      final completion = ProfileCompletion(
        profileExists: true,
        photoCount: 6,
        minimumPhotos: 4,
        hasName: true,
        hasBirthdate: true,
        hasCity: true,
        hasBio: true,
      );
      expect(completion.isComplete, isTrue);
      expect(completion.photosRemaining, 0);
    });

    test('photos alone are not enough: identity fields are required too', () {
      final completion = ProfileCompletion(
        profileExists: true,
        photoCount: 5,
        minimumPhotos: 4,
        hasName: false,
        hasBirthdate: true,
        hasCity: true,
        hasBio: false,
      );
      expect(completion.meetsPhotoMinimum, isTrue);
      expect(completion.isComplete, isFalse);
    });

    test('parses the server payload, which owns the rule', () {
      final parsed = ProfileCompletion.fromJson({
        'profile_exists': true,
        'photo_count': 2,
        'minimum_photos': 4,
        'has_name': true,
        'has_birthdate': true,
        'has_city': true,
        'has_bio': false,
      });
      expect(parsed.photoCount, 2);
      expect(parsed.minimumPhotos, 4);
      expect(parsed.photosRemaining, 2);
      expect(parsed.isComplete, isFalse);
    });

    test('the fallback default mirrors the database rule of 4', () {
      expect(ProfileCompletion.unknown.minimumPhotos, 4);
      expect(ProfileCompletion.unknown.isComplete, isFalse);
    });
  });
}
