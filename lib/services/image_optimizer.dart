import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Thrown when a picked image cannot be accepted, carrying text that is safe
/// and actionable to show to the user verbatim.
class ImageValidationException implements Exception {
  const ImageValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Quality tiers for profile photos.
///
/// The goal is a file small enough to upload quickly while still looking
/// sharp on a modern phone screen. Re-encoding a 2048px JPEG already
/// discards a lot of the original's data, so these are deliberately high:
/// the failure mode to avoid is a blurry, smeared face.
enum ImageQuality {
  /// Discovery cards and full-screen photo view.
  profile('Profile', maxDimension: 2048, jpegQuality: 88),

  /// Inline previews in lists.
  medium('Medium', maxDimension: 800, jpegQuality: 84),

  /// Avatars and grid thumbnails.
  thumbnail('Thumbnail', maxDimension: 400, jpegQuality: 80);

  const ImageQuality(
    this.label, {
    required this.maxDimension,
    required this.jpegQuality,
  });

  final String label;
  final int maxDimension;
  final int jpegQuality;

  static ImageQuality forDimension(int dimension) {
    if (dimension >= ImageQuality.profile.maxDimension) {
      return ImageQuality.profile;
    }
    if (dimension >= ImageQuality.medium.maxDimension) {
      return ImageQuality.medium;
    }
    return ImageQuality.thumbnail;
  }
}

/// Result of optimising one image.
class OptimizedImage {
  final Uint8List bytes;

  /// Pixel dimensions AFTER orientation correction, so callers that write
  /// width/height metadata record what the user actually sees.
  final int width;
  final int height;

  /// `image/jpeg` or `image/webp`.
  final String mimeType;
  final String extension;

  const OptimizedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.extension,
  });

  int get byteLength => bytes.length;

  String get prettySize {
    if (byteLength < 1024) return '$byteLength B';
    if (byteLength < 1024 * 1024) {
      return '${(byteLength / 1024).toStringAsFixed(0)} KB';
    }
    return '${(byteLength / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ImageOptimizer {
  /// Longest edge of a stored profile photo. 2048px is comfortably above a
  /// 1440p/3x phone screen, so photos stay sharp when zoomed.
  static const int maxDimension = 2048;

  static const int thumbnailDimension = 400;
  static const int mediumDimension = 800;

  /// Hard ceiling enforced before upload. The bucket's own limit is 10 MB;
  /// this is the app's own budget, comfortably under it.
  static const int maxFileSizeBytes = 2 * 1024 * 1024;

  /// Smallest accepted source edge. A 32x32 icon is not a dating-app photo,
  /// and upscaling it would produce a blurry, stretched result.
  static const int minDimension = 320;

  static const int maxSourceDimension = 8000;

  /// Why the last [pickAndOptimizeImage] call returned `null`, or `null` when
  /// the user simply cancelled. Callers surface this instead of guessing.
  static String? lastError;

  /// Validate raw bytes without re-encoding. Used by the upload path so an
  /// obviously-invalid payload is rejected before any network call.
  static void validate(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ImageValidationException(
        'That image could not be read. Please choose another.',
      );
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      throw const ImageValidationException(
        'That file is not a supported image. Please choose a JPG, PNG or WebP.',
      );
    }
    if (decoded.width < minDimension || decoded.height < minDimension) {
      throw ImageValidationException(
        'That photo is too small (${decoded.width}x${decoded.height}). '
        'Please choose one at least ${minDimension}x$minDimension pixels.',
      );
    }
    if (decoded.width > maxSourceDimension ||
        decoded.height > maxSourceDimension) {
      throw const ImageValidationException(
        'That photo is too large. Please choose one under '
        '$maxSourceDimension pixels on each side.',
      );
    }
  }

  /// Orient, resize and re-encode [bytes] at the given quality tier.
  ///
  /// Throws [ImageValidationException] with user-facing text when the input
  /// is unusable. The returned bytes are always a complete, valid image.
  ///
  /// EXIF orientation is APPLIED, not merely copied: the `image` package
  /// applies the transform during decode, so the pixels come out upright and
  /// the stale orientation tag is dropped along with the rest of the
  /// metadata by the re-encode.
  ///
  /// Only the longest edge is scaled and the short edge follows from the
  /// original ratio, so a portrait is never stretched into a squashed square.
  static Future<OptimizedImage> optimize(
    Uint8List bytes, {
    ImageQuality quality = ImageQuality.profile,
    bool preferWebP = true,
  }) async {
    validate(bytes);

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ImageValidationException(
        'That image could not be processed. Please choose another.',
      );
    }

    final bool landscape = decoded.width >= decoded.height;
    final int longest = landscape ? decoded.width : decoded.height;
    final resized = longest > quality.maxDimension
        ? img.copyResize(
            decoded,
            width: landscape ? quality.maxDimension : null,
            height: landscape ? null : quality.maxDimension,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final jpeg = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality.jpegQuality),
    );
    if (jpeg.isEmpty) {
      throw const ImageValidationException(
        'That image could not be processed. Please choose another.',
      );
    }

    var best = jpeg;
    var mime = 'image/jpeg';
    var ext = 'jpg';

    // `encodeWebP` in image 4.x is lossless-only (it has no quality knob),
    // so it is a candidate rather than a guaranteed win. Whichever encoder
    // produces the smaller file is kept; JPEG is always produced too,
    // because the Storage bucket's allowed_mime_types and older Android
    // WebP decoders are not something to depend on.
    if (preferWebP) {
      final webp = img.encodeWebP(resized);
      if (webp.isNotEmpty) {
        final webpBytes = Uint8List.fromList(webp);
        if (webpBytes.length < best.length) {
          best = webpBytes;
          mime = 'image/webp';
          ext = 'webp';
        }
      }
    }

    if (best.isEmpty) {
      throw const ImageValidationException(
        'That image could not be processed. Please choose another.',
      );
    }

    // The app's own upload budget. Re-encoding a noisy source can exceed it
    // even after a resize, so the tier steps down until it fits rather than
    // letting a multi-megabyte payload reach Storage and fail there with an
    // opaque "server error".
    if (best.length > maxFileSizeBytes && quality != ImageQuality.thumbnail) {
      return optimize(
        bytes,
        quality: quality == ImageQuality.profile
            ? ImageQuality.medium
            : ImageQuality.thumbnail,
        preferWebP: preferWebP,
      );
    }

    return OptimizedImage(
      bytes: best,
      width: resized.width,
      height: resized.height,
      mimeType: mime,
      extension: ext,
    );
  }

  /// Backwards-compatible byte-only entry point used by Edit Profile and
  /// Profile screens.
  static Future<Uint8List> optimizeImage(
    Uint8List bytes, {
    int? maxDimension,
  }) async {
    final tier = maxDimension == null
        ? ImageQuality.profile
        : ImageQuality.forDimension(maxDimension);
    final result = await optimize(bytes, quality: tier);
    return result.bytes;
  }

  static Future<Uint8List> createThumbnail(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    // Scale the longest edge only; the other follows the original ratio.
    final resized = image.width >= image.height
        ? img.copyResize(image, width: thumbnailDimension)
        : img.copyResize(image, height: thumbnailDimension);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  static Future<Uint8List> createMedium(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final resized = image.width >= image.height
        ? img.copyResize(image, width: mediumDimension)
        : img.copyResize(image, height: mediumDimension);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 84));
  }

  /// Pick an image and re-encode it as a valid, size-bounded JPEG.
  ///
  /// Returns `null` only when the user cancelled or the picker itself failed
  /// (already reported through [lastError]). A file that cannot be decoded is
  /// reported as an error instead of being passed through unchanged: a
  /// HEIC/RAW/corrupt payload would be rejected by the bucket's
  /// `allowed_mime_types` and surface later as an unexplained upload failure.
  static Future<File?> pickAndOptimizeImage() async {
    lastError = null;
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 100,
      );
      if (image == null) return null;
      final bytes = await image.readAsBytes();

      // A file that cannot be decoded or is too small/large is reported as a
      // real error instead of being passed through: a HEIC/RAW/corrupt
      // payload would be rejected by the bucket's allowed_mime_types and
      // surface later as an unexplained upload failure.
      final OptimizedImage optimized;
      try {
        optimized = await optimize(bytes);
      } on ImageValidationException catch (e) {
        lastError = e.message;
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/weekend_${DateTime.now().microsecondsSinceEpoch}'
        '.${optimized.extension}',
      );
      await file.writeAsBytes(optimized.bytes, flush: true);
      return file;
    } on PlatformException catch (e) {
      lastError = e.code == 'camera_access_denied'
          ? 'Photo access was denied. Enable it in Settings to continue.'
          : 'Could not open the image picker.';
      debugPrint('Image picker error: $e');
      return null;
    } catch (e) {
      lastError = 'Could not read that image. Please choose another.';
      debugPrint('Image pick failed: $e');
      return null;
    }
  }
}
