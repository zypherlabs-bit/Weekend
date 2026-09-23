// Gender preference filtering tests for Weekend discovery
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';

void main() {
  group('LocationPreferences', () {
    test('default has empty preferredGenders', () {
      const prefs = LocationPreferences();
      expect(prefs.preferredGenders, isEmpty);
    });

    test('can set preferredGenders to single gender', () {
      const prefs = LocationPreferences(preferredGenders: ['Man']);
      expect(prefs.preferredGenders, ['Man']);
    });

    test('can set preferredGenders to multiple genders', () {
      const prefs = LocationPreferences(preferredGenders: ['Man', 'Woman']);
      expect(prefs.preferredGenders, ['Man', 'Woman']);
    });
    test('copyWith preserves preferredGenders when not specified', () {
      const original = LocationPreferences(preferredGenders: ['Woman']);
      final copied = original.copyWith(discoveryRadiusKm: 50);
      expect(copied.preferredGenders, ['Woman']);
    });

    test('fromJson deserializes preferredGenders', () {
      final json = {
        'preferred_genders': ['Man', 'Non-binary'],
        'discovery_radius_km': 25,
      };
      final prefs = LocationPreferences.fromJson(json);
      expect(prefs.preferredGenders, ['Man', 'Non-binary']);
    });

    test('fromJson returns empty list when preferredGenders not in json', () {
      final json = {'discovery_radius_km': 25};
      final prefs = LocationPreferences.fromJson(json);
      expect(prefs.preferredGenders, isEmpty);
    });
  });

  group('Gender filtering logic', () {
    test('empty preference shows all genders', () {
      final preferences = <String>[];
      final profiles = [
        UserProfile(id: '1', name: 'Alice', age: 25, gender: 'Woman', photos: [],
            city: '', distanceKm: 0, bio: ''),
        UserProfile(id: '2', name: 'Bob', age: 30, gender: 'Man', photos: [],
            city: '', distanceKm: 0, bio: ''),
      ];

      final filtered = profiles.where((p) {
        if (preferences.isEmpty) return true;
        return preferences.contains(p.gender);
      }).toList();

      expect(filtered.length, 2);
    });

    test('Man preference shows only male profiles', () {
      final preferences = ['Man'];
      final profiles = [
        UserProfile(id: '1', name: 'Alice', age: 25, gender: 'Woman', photos: [],
            city: '', distanceKm: 0, bio: ''),
        UserProfile(id: '2', name: 'Bob', age: 30, gender: 'Man', photos: [],
            city: '', distanceKm: 0, bio: ''),
      ];

      final filtered = profiles.where((p) {
        if (preferences.isEmpty) return true;
        return preferences.contains(p.gender);
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.gender, 'Man');
    });
  });
}