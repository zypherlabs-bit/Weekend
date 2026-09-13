import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:weekend/services/location_service.dart';

void main() {
  group('Geohash', () {
    test('encode produces correct length geohash for known coordinate', () {
      final hash = Geohash.encode(48.85884, 2.29435, precision: 7);
      expect(hash.length, 7);
      expect(hash, 'u09tunq');
    });

    test('encode with precision 6', () {
      final hash = Geohash.encode(48.85884, 2.29435, precision: 6);
      expect(hash.length, 6);
      expect(hash, 'u09tun');
    });

    test('encode with default precision 7', () {
      final hash = Geohash.encode(40.712776, -74.005974);
      expect(hash.length, 7);
    });

    test('decode correctly reverses encode', () {
      const lat = 48.85884;
      const lon = 2.29435;

      final encoded = Geohash.encode(lat, lon, precision: 7);
      final decoded = Geohash.decode(encoded);

      expect(decoded[0], closeTo(lat, 0.001));
      expect(decoded[1], closeTo(lon, 0.001));
    });

    test('decode of known geohash returns expected range', () {
      final result = Geohash.decode('u09tunq');
      expect(result.length, 2);
      expect(result[0], closeTo(48.8588, 0.01));
      expect(result[1], closeTo(2.294, 0.01));
    });

    test('adjacent coordinates produce same prefix at low precision', () {
      final hash1 = Geohash.encode(48.8580, 2.2940, precision: 4);
      final hash2 = Geohash.encode(48.8590, 2.2950, precision: 4);
      expect(hash1, hash2);
    });

    test('distant coordinates produce different geohash', () {
      final hash1 = Geohash.encode(48.8567, 2.3510, precision: 7);
      final hash2 = Geohash.encode(40.7128, -74.0060, precision: 7);
      expect(hash1, isNot(hash2));
    });

    test('encodeFromPosition uses position coordinates', () {
      final position = geolocator.Position(
        latitude: 48.85884,
        longitude: 2.29435,
        timestamp: DateTime(2024, 1, 1),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final hash = Geohash.encodeFromPosition(position, precision: 7);
      expect(hash, 'u09tunq');
    });
  });

  group('Geohash precision', () {
    test('precision 7 is approximately 150m resolution', () {
      const lat = 48.85884;
      const lon = 2.29435;

      final hash = Geohash.encode(lat, lon, precision: 7);
      final decoded = Geohash.decode(hash);

      final latError = (decoded[0] - lat).abs();
      final lonError = (decoded[1] - lon).abs();

      expect(latError, lessThan(0.001));
      expect(lonError, lessThan(0.001));
    });

    test('precision determines bucket resolution', () {
      for (var p = 1; p <= 12; p++) {
        final hash = Geohash.encode(48.85884, 2.29435, precision: p);
        expect(hash.length, p);
      }
    });

    test('precision 1 covers large area', () {
      final hash = Geohash.encode(48.85884, 2.29435, precision: 1);
      expect(hash.length, 1);
      final decoded = Geohash.decode(hash);
      expect(decoded[0], inInclusiveRange(-90, 90));
      expect(decoded[1], inInclusiveRange(-180, 180));
    });
  });
}
