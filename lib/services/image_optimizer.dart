import 'package:flutter/material.dart';
import 'dart:typed_data';
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

  static Future<Uint8List> optimizeImage(Uint8List bytes, {int? maxDimension}) async {
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

  static Future<File?> pickAndOptimizeImage() async {
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
      final optimized = await optimizeImage(bytes);
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/optimized_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(optimized);
      
      return file;
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
      return null;
    }
  }
}
