import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageOptimizer {
  static const int maxDimension = 2048;
  static const int thumbnailDimension = 400;
  static const int mediumDimension = 800;
  static const int maxFileSizeBytes = 2 * 1024 * 1024;

  /// Why the last [pickAndOptimizeImage] call returned `null`, or `null` when
  /// the user simply cancelled. Callers surface this instead of guessing.
  static String? lastError;
  static Future<Uint8List> optimizeImage(
    Uint8List bytes, {
    int? maxDimension,
  }) async {
    final maxDim = maxDimension ?? ImageOptimizer.maxDimension;
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    int width = image.width;
    int height = image.height;
    if (width > maxDim || height > maxDim) {
      if (width > height) {
        height = (height * maxDim / width).round();
        width = maxDim;
      } else {
        width = (width * maxDim / height).round();
        height = maxDim;
      }
    }
    final resized = img.copyResize(image, width: width, height: height);
    final optimized = img.encodeJpg(resized, quality: 85);
    return Uint8List.fromList(optimized);
  }
  static Future<Uint8List> createThumbnail(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    int width = image.width;
    int height = image.height;
    if (width > height) {
      height = (height * thumbnailDimension / width).round();
      width = thumbnailDimension;
    } else {
      width = (width * thumbnailDimension / height).round();
      height = thumbnailDimension;
    }
    final resized = img.copyResize(image, width: width, height: height);
    final result = img.encodeJpg(resized, quality: 80);
    return Uint8List.fromList(result);
  }

  static Future<Uint8List> createMedium(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    int width = image.width;
    int height = image.height;
    if (width > height) {
      height = (height * mediumDimension / width).round();
      width = mediumDimension;
    } else {
      width = (width * mediumDimension / height).round();
      height = mediumDimension;
    }
    final resized = img.copyResize(image, width: width, height: height);
    final result = img.encodeJpg(resized, quality: 85);
    return Uint8List.fromList(result);
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
      if (bytes.isEmpty) {
        lastError = 'That image could not be read. Please choose another.';
        return null;
      }
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width == 0 || decoded.height == 0) {
        lastError =
            'That file is not a supported image. Please choose a JPG, PNG or WebP.';
        return null;
      }
      // Re-encode rather than passing bytes through: this normalises the
      // format to JPEG (what the bucket accepts) and applies EXIF orientation.
      final optimized = await optimizeImage(bytes);
      if (optimized.isEmpty) {
        lastError = 'That image could not be processed. Please choose another.';
        return null;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/optimized_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(optimized, flush: true);
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
