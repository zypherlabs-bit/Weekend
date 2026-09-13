import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:weekend/services/location_service.dart';

void main() {
  group('LocationService Utility Methods', () {
    group('formatDistance', () {
      test('formats meters for distances under 1 km', () {
        expect(LocationService.formatDistance(0.5), '500 m');
        expect(LocationService.formatDistance(0.25), '250 m');
        expect(LocationService.formatDistance(0.1), '100 m');
      });

      test('formats km with decimals for distances 1-10 km', () {
        expect(LocationService.formatDistance(1.0), '1.0 km');
        expect(LocationService.formatDistance(2.5), '2.5 km');
        expect(LocationService.formatDistance(9.9), '9.9 km');
      });

      test('formats km as integer for distances 10+ km', () {
        expect(LocationService.formatDistance(10.0), '10 km');
        expect(LocationService.formatDistance(50.5), '51 km');
        expect(LocationService.formatDistance(100.0), '100 km');
      });
    });

    group('formatDistanceWithAway', () {
      test('formats with "away" suffix for meters', () {
        expect(LocationService.formatDistanceWithAway(0.5), '500 m away');
      });

      test('formats with "away" suffix for km', () {
        expect(LocationService.formatDistanceWithAway(5.0), '5.0 km away');
        expect(LocationService.formatDistanceWithAway(25.0), '25 km away');
      });
    });

    group('toApproximateCoordinates', () {
      test('rounds coordinates to grid', () {
        final (lat, lon) = LocationService.toApproximateCoordinates(
          48.8566, 2.3522, 1.0,
        );

        final (lat2, lon2) = LocationService.toApproximateCoordinates(
          48.8570, 2.3525, 1.0,
        );

        expect(lat, closeTo(48.8566, 0.01));
        expect(lon, closeTo(2.3522, 0.01));
        expect(lat2, closeTo(lat, 0.01));
        expect(lon2, closeTo(lon, 0.01));
      });

      test('different grids produce different results for distant points', () {
        final (lat1, lon1) = LocationService.toApproximateCoordinates(
          40.7128, -74.0060, 1.0,
        );
        final (lat2, lon2) = LocationService.toApproximateCoordinates(
          48.8567, 2.3522, 1.0,
        );

        expect(lat1, isNot(closeTo(lat2, 0.1)));
        expect(lon1, isNot(closeTo(lon2, 0.1)));
      });
    });

    group('isWithinRadius', () {
      test('returns true for nearby points', () {
        final result = LocationService.isWithinRadius(
          48.8567, 2.3522, 48.8570, 2.3525, 5.0,
        );
        expect(result, true);
      });

      test('returns false for distant points', () {
        final result = LocationService.isWithinRadius(
          48.8567, 2.3522, 40.7128, -74.0060, 5.0,
        );
        expect(result, false);
      });

      test('boundary check', () {
        final result = LocationService.isWithinRadius(
          0.0, 0.0, 0.0, 1.0, 112,
        );
        expect(result, true);
      });
    });

    group('distanceInKm', () {
      test('calculates distance between close coordinates', () {
        final distance = LocationService.distanceInKm(
          48.8567, 2.3522, 48.8570, 2.3525,
        );
        expect(distance, lessThan(1.0));
      });

      test('calculates distance between far coordinates', () {
        final distance = LocationService.distanceInKm(
          48.8567, 2.3522, 40.7128, -74.0060,
        );
        expect(distance, greaterThan(5000));
      });

      test('returns 0 for identical coordinates', () {
        final distance = LocationService.distanceInKm(
          48.8567, 2.3522, 48.8567, 2.3522,
        );
        expect(distance, closeTo(0, 0.001));
      });
    });

    group('supportedRadii', () {
      test('includes standard radius values', () {
        expect(LocationService.supportedRadii, containsAll([0.5, 1, 5]));
      });

      test('includes larger radius values', () {
        expect(LocationService.supportedRadii, containsAll([50, 100]));
      });

      test('is non-empty', () {
        expect(LocationService.supportedRadii, isNotEmpty);
      });
    });

    group('getGeohashBucket', () {
      test('produces consistent geohash for same position', () {
        final position = geolocatorPosition(48.8567, 2.3522);
        final bucket1 = LocationService.getGeohashBucket(position);
        final bucket2 = LocationService.getGeohashBucket(position);
        expect(bucket1, bucket2);
      });

      test('different positions yield different buckets', () {
        final pos1 = geolocatorPosition(48.8567, 2.3522);
        final pos2 = geolocatorPosition(40.7128, -74.0060);
        final bucket1 = LocationService.getGeohashBucket(pos1);
        final bucket2 = LocationService.getGeohashBucket(pos2);
        expect(bucket1, isNot(bucket2));
      });

      test('nearby positions may share the same bucket', () {
        final pos1 = geolocatorPosition(48.8567, 2.3522);
        final pos2 = geolocatorPosition(48.8568, 2.3523);
        final bucket1 = LocationService.getGeohashBucket(pos1);
        final bucket2 = LocationService.getGeohashBucket(pos2);
        // Precision 7 is ~150m, so nearby coordinates in same city should match
        expect(bucket1, equals(bucket2));
      });
    });
  });
}

geolocatorPosition(double lat, double lon) {
  return geolocator.Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
