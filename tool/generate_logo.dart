import 'dart:io';
import 'package:image/image.dart';

void main() {
  const int size = 1024;
  
  final image = Image(width: size, height: size);
  
  // Fill with transparent
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixel(x, y, Color(0, 0, 0, 0));
    }
  }
  
  // Background gradient circle
  final centerX = size / 2;
  final centerY = size / 2;
  final radius = size * 0.48;
  
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - centerX;
      final dy = y - centerY;
      final distSq = dx * dx + dy * dy;
      if (distSq <= radius * radius) {
        final t = distSq / (radius * radius);
        final r = 255;
        final g = (75 + (153 - 75) * t).round();
        final b = (114 + (102 - 114) * t).round();
        image.setPixel(x, y, Color(r, g, b, 255));
      }
    }
  }
  
  // Draw the "W" shape with simple lines
  final strokeWidth = (size * 0.045).round();
  final pathColor = Color(255, 255, 255, 255);
  
  final scale = size / 512;
  final cx = centerX;
  final cy = centerY;
  final iconScale = 0.5 * scale;
  
  // Left vertical
  drawLine(image, 
    (cx - 90 * iconScale).round(), (cy - 60 * iconScale).round(),
    (cx - 90 * iconScale).round(), (cy + 60 * iconScale).round(),
    pathColor, strokeWidth);
  
  // Left valley to center peak
  drawQuadraticCurve(image,
    (cx - 90 * iconScale).round(), (cy + 60 * iconScale).round(),
    (cx - 45 * iconScale).round(), (cy).round(),
    (cx - 45 * iconScale).round(), (cy - 60 * iconScale).round(),
    pathColor, strokeWidth);
  
  // Center peak to right valley
  drawQuadraticCurve(image,
    (cx - 45 * iconScale).round(), (cy - 60 * iconScale).round(),
    (cx).round(), (cy - 60 * iconScale).round(),
    (cx).round(), (cy).round(),
    pathColor, strokeWidth);
  
  drawQuadraticCurve(image,
    (cx).round(), (cy).round(),
    (cx + 45 * iconScale).round(), (cy + 60 * iconScale).round(),
    (cx + 45 * iconScale).round(), (cy).round(),
    pathColor, strokeWidth);
  
  drawQuadraticCurve(image,
    (cx + 45 * iconScale).round(), (cy).round(),
    (cx + 90 * iconScale).round(), (cy - 60 * iconScale).round(),
    (cx + 90 * iconScale).round(), (cy + 60 * iconScale).round(),
    pathColor, strokeWidth);
  
  // Right vertical
  drawLine(image,
    (cx + 90 * iconScale).round(), (cy + 60 * iconScale).round(),
    (cx + 90 * iconScale).round(), (cy - 60 * iconScale).round(),
    pathColor, strokeWidth);
  
  // Dots
  fillCircle(image, (cx - 90 * iconScale).round(), (cy - 60 * iconScale).round(), (8 * iconScale).round(), Color(255, 75, 114, 255));
  fillCircle(image, (cx).round(), (cy - 60 * iconScale).round(), (10 * iconScale).round(), Color(255, 153, 102, 255));
  fillCircle(image, (cx + 90 * iconScale).round(), (cy - 60 * iconScale).round(), (8 * iconScale).round(), Color(255, 75, 114, 255));
  fillCircle(image, (cx - 90 * iconScale).round(), (cy + 60 * iconScale).round(), (6 * iconScale).round(), Color(255, 153, 102, 255));
  fillCircle(image, (cx + 90 * iconScale).round(), (cy + 60 * iconScale).round(), (6 * iconScale).round(), Color(255, 153, 102, 255));
  
  // Sparkles
  fillCircle(image, (cx - 116 * iconScale).round(), (cy - 116 * iconScale).round(), (4 * iconScale).round(), Color(255, 255, 255, 255));
  fillCircle(image, (cx + 124 * iconScale).round(), (cy + 124 * iconScale).round(), (3 * iconScale).round(), Color(255, 255, 255, 255));
  fillCircle(image, (cx - 136 * iconScale).round(), (cy + 134 * iconScale).round(), (3 * iconScale).round(), Color(255, 255, 255, 255));
  fillCircle(image, (cx + 134 * iconScale).round(), (cy - 136 * iconScale).round(), (4 * iconScale).round(), Color(255, 255, 255, 255));
  
  // Inner ring
  drawCircle(image, centerX.round(), centerY.round(), (radius * 0.88).round(), Color(255, 255, 255, 76), 4);
  
  // Save as PNG
  final pngBytes = encodePng(image);
  File('assets/icons/weekend_logo.png').writeAsBytesSync(pngBytes);
  
  print('Generated weekend_logo.png');
}

void drawLine(Image image, int x1, int y1, int x2, int y2, Color color, int width) {
  final dx = (x2 - x1).abs();
  final dy = (y2 - y1).abs();
  final sx = x1 < x2 ? 1 : -1;
  final sy = y1 < y2 ? 1 : -1;
  var err = dx - dy;
  var x = x1;
  var y = y1;
  
  while (true) {
    fillCircle(image, x, y, width ~/ 2, color);
    if (x == x2 && y == y2) break;
    final e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x += sx; }
    if (e2 < dx) { err += dx; y += sy; }
  }
}

void drawQuadraticCurve(Image image, int x1, int y1, int cx, int cy, int x2, int y2, Color color, int width) {
  for (int i = 0; i <= 100; i++) {
    final t = i / 100;
    final mt = 1 - t;
    final x = (mt * mt * x1 + 2 * mt * t * cx + t * t * x2).round();
    final y = (mt * mt * y1 + 2 * mt * t * cy + t * t * y2).round();
    fillCircle(image, x, y, width ~/ 2, color);
  }
}

void fillCircle(Image image, int cx, int cy, int radius, Color color) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      if (x * x + y * y <= radius * radius) {
        final px = cx + x;
        final py = cy + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}

void drawCircle(Image image, int cx, int cy, int radius, Color color, int width) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      final distSq = x * x + y * y;
      final inner = (radius - width / 2) * (radius - width / 2);
      final outer = (radius + width / 2) * (radius + width / 2);
      if (distSq >= inner && distSq <= outer) {
        final px = cx + x;
        final py = cy + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}