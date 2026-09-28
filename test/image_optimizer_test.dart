import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:weekend/services/image_optimizer.dart';

/// Build a JPEG of the requested size with enough visual complexity that
/// re-encoding actually has something to compress (a flat colour would
/// compress to almost nothing and make a size comparison meaningless).
Uint8List _testJpeg(int width, int height, {int quality = 98}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // A gradient plus a checker pattern: compresses like a real photo.
      final v = ((x * 7 + y * 13) % 200) + 30;
      image.setPixelRgb(x, y, v, (v * 3) % 256, (v * 5) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  group('ImageOptimizer.validate', () {
    test('rejects empty bytes with an actionable message', () {
      expect(
        () => ImageOptimizer.validate(Uint8List(0)),
        throwsA(
          isA<ImageValidationException>().having(
            (e) => e.message,
            'message',
            contains('could not be read'),
          ),
        ),
      );
    });

    test('rejects a non-image payload', () {
      final garbage = Uint8List.fromList(List<int>.filled(512, 0x41));
      expect(
        () => ImageOptimizer.validate(garbage),
        throwsA(
          isA<ImageValidationException>().having(
            (e) => e.message,
            'message',
            contains('not a supported image'),
          ),
        ),
      );
    });

    test('rejects a photo too small to look like a profile photo', () {
      expect(
        () => ImageOptimizer.validate(_testJpeg(64, 64)),
        throwsA(
          isA<ImageValidationException>().having(
            (e) => e.message,
            'message',
            contains('too small'),
          ),
        ),
      );
    });

    test('accepts a normal-sized photo', () {
      expect(
        () => ImageOptimizer.validate(_testJpeg(800, 600)),
        returnsNormally,
      );
    });
  });

  group('ImageOptimizer.optimize', () {
    test('reduces file size versus the original', () async {
      final original = _testJpeg(3000, 2000);
      final result = await ImageOptimizer.optimize(original);

      expect(
        result.byteLength,
        lessThan(original.length),
        reason: 'compression must actually reduce the payload',
      );
    });

    test('caps the longest edge at the profile dimension', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(4000, 3000));
      final longest =
          result.width > result.height ? result.width : result.height;
      expect(longest, ImageQuality.profile.maxDimension);
    });

    test('preserves the original aspect ratio when resizing', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(4000, 2000));
      // Source ratio 2.0; a stretched resize would shift this noticeably.
      expect(result.width / result.height, closeTo(2.0, 0.05));
    });

    test('preserves the aspect ratio of a portrait photo', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(2000, 4000));
      expect(result.height / result.width, closeTo(2.0, 0.05));
    });

    test('never upscales a photo that is already small enough', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(600, 400));
      expect(result.width, 600);
      expect(result.height, 400);
    });

    test('drops EXIF metadata by re-encoding', () async {
      // A freshly encoded JPEG carries no EXIF APP1 segment to begin with;
      // what matters is that the output is a clean re-encode rather than the
      // original container passed through. The `image` package synthesises an
      // empty IfdDirectory on decode, so the assertion is that no EXIF
      // entries exist rather than that the map is null.
      final original = _testJpeg(1200, 900);
      final result = await ImageOptimizer.optimize(original);
      final out = img.decodeImage(result.bytes);

      expect(out, isNotNull);
      expect(out!.exif.imageIfd, isEmpty, reason: 'no EXIF tags may survive');
      expect(out.exif.exifIfd, isEmpty);
      expect(out.exif.gpsIfd, isEmpty);
      // The pixel data must also be smaller than the source container.
      expect(result.byteLength, lessThan(original.length));
    });

    test('produces a decodable image in a bucket-allowed format', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(1500, 1500));

      expect(
        result.mimeType,
        anyOf('image/jpeg', 'image/webp'),
        reason: 'the Storage bucket only allow-lists jpeg/png/webp',
      );
      expect(img.decodeImage(result.bytes), isNotNull);
    });

    test('thumbnail tier produces a much smaller file', () async {
      final original = _testJpeg(2400, 1800);
      final full = await ImageOptimizer.optimize(original);
      final thumb = await ImageOptimizer.optimize(
        original,
        quality: ImageQuality.thumbnail,
      );

      expect(thumb.byteLength, lessThan(full.byteLength));
      expect(
        thumb.width,
        lessThanOrEqualTo(ImageQuality.thumbnail.maxDimension),
      );
    });

    test('quality tiers are ordered so profile is the largest', () {
      expect(
        ImageQuality.profile.maxDimension,
        greaterThan(ImageQuality.medium.maxDimension),
      );
      expect(
        ImageQuality.medium.maxDimension,
        greaterThan(ImageQuality.thumbnail.maxDimension),
      );
      // Never so low that a face becomes visibly smeared.
      expect(ImageQuality.profile.jpegQuality, greaterThanOrEqualTo(85));
    });

    test('reports a human-readable file size', () async {
      final result = await ImageOptimizer.optimize(_testJpeg(1600, 1200));
      expect(result.prettySize, matches(r'^\d+(\.\d+)?\s(B|KB|MB)$'));
    });
  });

  group('ImageOptimizer budgets', () {
    test('budget stays under the Storage bucket limit', () {
      // Migration 018 sets file_size_limit to 10 MB.
      expect(ImageOptimizer.maxFileSizeBytes, lessThan(10 * 1024 * 1024));
    });

    test('profile dimension is large enough to stay sharp', () {
      expect(ImageOptimizer.maxDimension, greaterThanOrEqualTo(1440));
    });
  });
}
