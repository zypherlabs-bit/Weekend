import 'dart:io';
import 'package:image/image.dart' as img;

/// Generates the transparent adaptive-icon foreground for the Weekend logo.
///
/// The foreground contains only the "W" connection glyph, centered and sized
/// inside the adaptive-icon safe zone (~66% of the canvas), so Android can
/// place it on the solid gradient background color.
void main() {
  const int size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);

  // Transparent background
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  const scale = size / 512.0;
  const cx = size / 2.0;
  const cy = size / 2.0;
  // Slight upscale so the W footprint occupies the adaptive safe zone.
  final g = 1.35 * scale;
  final stroke = (24 * g).round();
  final white = img.ColorRgba8(255, 255, 255, 255);
  final coral = img.ColorRgba8(255, 75, 114, 255);
  final peach = img.ColorRgba8(255, 153, 102, 255);

  double X(double v) => cx + v * g;
  double Y(double v) => cy + v * g;

  // Left vertical
  _line(image, X(-90), Y(-60), X(-90), Y(60), white, stroke);
  // Left valley -> center peak
  _quad(image, X(-90), Y(60), X(-45), Y(60), X(-45), Y(0), white, stroke);
  _quad(image, X(-45), Y(0), X(-45), Y(-60), X(0), Y(-60), white, stroke);
  // Center peak -> right valley
  _quad(image, X(0), Y(-60), X(45), Y(-60), X(45), Y(0), white, stroke);
  _quad(image, X(45), Y(0), X(45), Y(60), X(90), Y(60), white, stroke);
  // Right vertical
  _line(image, X(90), Y(60), X(90), Y(-60), white, stroke);

  // Connection dots
  _circle(image, X(-90), Y(-60), (8 * g).round(), coral);
  _circle(image, X(0), Y(-60), (10 * g).round(), peach);
  _circle(image, X(90), Y(-60), (8 * g).round(), coral);
  _circle(image, X(-90), Y(60), (6 * g).round(), peach);
  _circle(image, X(90), Y(60), (6 * g).round(), peach);

  final fgBytes = img.encodePng(image);
  File('assets/icons/weekend_logo_fg.png').writeAsBytesSync(fgBytes);
  print('Generated assets/icons/weekend_logo_fg.png');

  // Full logo: coral->peach gradient circle with glow, inner ring, sparkles.
  final full = img.Image(width: size, height: size, numChannels: 4);
  img.fill(full, color: img.ColorRgba8(0, 0, 0, 0));
  final r = size * 0.48;
  final cx0 = size / 2.0;
  final cy0 = size / 2.0;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - cx0;
      final dy = y - cy0;
      final distSq = dx * dx + dy * dy;
      if (distSq <= r * r) {
        final t = distSq / (r * r);
        final rr = 255;
        final gg = (75 + (153 - 75) * t).round();
        final bb = (114 + (102 - 114) * t).round();
        // soft glow halo
        if (distSq <= r * r && distSq >= (r * 0.94) * (r * 0.94)) {
          final a = ((1 - (distSq - (r * 0.94) * (r * 0.94)) /
                  (r * r - (r * 0.94) * (r * 0.94))) *
                  70)
              .round();
          full.setPixel(x, y, img.ColorRgba8(rr, gg, bb, 255 - a));
        } else {
          full.setPixel(x, y, img.ColorRgba8(rr, gg, bb, 255));
        }
      }
    }
  }
  // Inner translucent ring
  _circle(full, cx0, cy0, (r * 0.88).round(),
      img.ColorRgba8(255, 255, 255, 60));
  _annulus(full, cx0, cy0, (r * 0.88).round(), 4,
      img.ColorRgba8(255, 255, 255, 60));
  // Sparkles
  _circle(full, cx0 - 116 * 1.35, cy0 - 116 * 1.35, 5,
      img.ColorRgba8(255, 255, 255, 200));
  _circle(full, cx0 + 124 * 1.35, cy0 + 124 * 1.35, 4,
      img.ColorRgba8(255, 255, 255, 150));
  _circle(full, cx0 - 136 * 1.35, cy0 + 134 * 1.35, 4,
      img.ColorRgba8(255, 255, 255, 130));
  _circle(full, cx0 + 134 * 1.35, cy0 - 136 * 1.35, 5,
      img.ColorRgba8(255, 255, 255, 180));
  final fullPng = img.encodePng(full);
  File('assets/icons/weekend_logo.png').writeAsBytesSync(fullPng);
  print('Generated assets/icons/weekend_logo.png');
}

void _annulus(img.Image image, double cx, double cy, int radius, int width,
    img.Color color) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      final distSq = (x * x + y * y).toDouble();
      final inner = (radius - width / 2) * (radius - width / 2);
      final outer = (radius + width / 2) * (radius + width / 2);
      if (distSq >= inner && distSq <= outer) {
        final px = cx.round() + x;
        final py = cy.round() + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}

void _line(
    img.Image image, double x1, double y1, double x2, double y2,
    img.Color color, int width) {
  final dx = (x2 - x1).abs();
  final dy = (y2 - y1).abs();
  final sx = x1 < x2 ? 1 : -1;
  final sy = y1 < y2 ? 1 : -1;
  var err = dx - dy;
  var x = x1;
  var y = y1;
  while (true) {
    _circle(image, x, y, width ~/ 2, color);
    if ((x - x2).abs() < 0.5 && (y - y2).abs() < 0.5) break;
    final e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x += sx;
    }
    if (e2 < dx) {
      err += dx;
      y += sy;
    }
  }
}

void _quad(img.Image image, double x1, double y1, double cx, double cy,
    double x2, double y2, img.Color color, int width) {
  for (int i = 0; i <= 120; i++) {
    final t = i / 120;
    final mt = 1 - t;
    final x = mt * mt * x1 + 2 * mt * t * cx + t * t * x2;
    final y = mt * mt * y1 + 2 * mt * t * cy + t * t * y2;
    _circle(image, x, y, width ~/ 2, color);
  }
}

void _circle(img.Image image, double cx, double cy, int radius, img.Color color) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      if (x * x + y * y <= radius * radius) {
        final px = cx.round() + x;
        final py = cy.round() + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}