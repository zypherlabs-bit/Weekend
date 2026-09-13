import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/services/location_service.dart';

void main() {
  group('DiscoveryRepository Logic', () {
    group('Geohash bucket consistency', () {
      test('same location produces same geohash', () {
        final hash1 = Geohash.encode(48.8567, 2.3522, precision: 7);
        final hash2 = Geohash.encode(48.8567, 2.3522, precision: 7);
        expect(hash1, hash2);
      });

      test('different cities produce different geohash', () {
        final paris = Geohash.encode(48.8567, 2.3522, precision: 7);
        final nyc = Geohash.encode(40.7128, -74.0060, precision: 7);
        expect(paris, isNot(nyc));
      });

      test('geohash encodes/decodes round-trip', () {
        const lat = 37.7749;
        const lon = -122.4194;
        final hash = Geohash.encode(lat, lon, precision: 7);
        final decoded = Geohash.decode(hash);
        expect(decoded[0], closeTo(lat, 0.001));
        expect(decoded[1], closeTo(lon, 0.001));
      });

      test('toApproximateCoordinates returns nearby grid', () {
        final (lat, lon) = LocationService.toApproximateCoordinates(
          48.8567, 2.3522, 2.0,
        );
        expect(lat, inInclusiveRange(48.8, 48.9));
        expect(lon, inInclusiveRange(2.3, 2.4));
      });

      test('distance computation is accurate', () {
        final distance = LocationService.distanceInKm(
          48.8567, 2.3522,
          48.8570, 2.3525,
        );
        expect(distance, lessThan(0.5));
      });

      test('isWithinRadius works for known distances', () {
        final isIn5km = LocationService.isWithinRadius(
          48.8567, 2.3522,
          48.8570, 2.3525,
          5.0,
        );
        expect(isIn5km, true);

        final tooFar = LocationService.isWithinRadius(
          48.8567, 2.3522,
          40.7128, -74.0060,
          5.0,
        );
        expect(tooFar, false);
      });
    });

    group('Location preferences privacy', () {
      test('approximate coordinates are not exact originals', () {
        const originalLat = 48.8567123;
        const originalLon = 2.3522345;
        final (lat, lon) = LocationService.toApproximateCoordinates(
          originalLat, originalLon, 2.0,
        );
        expect(lat, isNot(equals(originalLat)));
        expect(lon, isNot(equals(originalLon)));
      });
    });
  });
}
