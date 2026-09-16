import 'dart:io';
import 'package:image/image.dart' as img;

/// Generates the neutral Weekend placeholder artwork used by the UI.
///
/// Output:
///   * `assets/images/placeholder_avatar.png` — a brand-coloured silhouette
///     used as a cover image for cards that have no photo yet (see
///     `lib/features/discovery/explore_screen.dart`).
///
/// The image contains no personal data and no third-party artwork: it is
/// drawn from scratch with the Weekend palette (coral `#FF4B72` →
/// peach `#FF9966` on the deep plum `#130E20` canvas).
///
/// Run with:
///   dart run tool/generate_placeholder_assets.dart
void main() {
  const int size = 512;
  const int ss = 2; // supersampling factor for smooth edges
  const int canvas = size * ss;

  final image = img.Image(width: canvas, height: canvas, numChannels: 4);

  // Deep plum vertical gradient background (#2E244A -> #130E20).
  for (int y = 0; y < canvas; y++) {
    final t = y / (canvas - 1);
    final r = (0x2E + (0x13 - 0x2E) * t).round();
    final g = (0x24 + (0x0E - 0x24) * t).round();
    final b = (0x4A + (0x20 - 0x4A) * t).round();
    final row = img.ColorRgba8(r, g, b, 255);
    for (int x = 0; x < canvas; x++) {
      image.setPixel(x, y, row);
    }
  }

  final cx = canvas / 2.0;
  final cy = canvas / 2.0;

  // Soft coral halo behind the silhouette.
  _radial(image, cx, cy * 0.86, canvas * 0.42,
      img.ColorRgba8(0xFF, 0x4B, 0x72, 26), img.ColorRgba8(0x00, 0x00, 0x00, 0));

  // Person silhouette: head + shoulders, drawn in the Weekend gradient.
  _disc(image, cx, canvas * 0.38, canvas * 0.135, img.ColorRgba8(0xFF, 0x4B, 0x72, 235));
  _halfEllipse(
    image,
    cx,
    canvas * 0.84,
    canvas * 0.265,
    canvas * 0.245,
    img.ColorRgba8(0xFF, 0x99, 0x66, 0xE0),
  );

  final downsampled = img.copyResize(
    image,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );

  const outPath = 'assets/images/placeholder_avatar.png';
  File(outPath).writeAsBytesSync(img.encodePng(downsampled));
  print('Generated $outPath');
}

/// Fills a disc of [radius] centred at ([cx], [cy]).
void _disc(img.Image image, double cx, double cy, double radius, img.Color color) {
  final r2 = radius * radius;
  for (int y = (cy - radius).floor(); y <= (cy + radius).ceil(); y++) {
    for (int x = (cx - radius).floor(); x <= (cx + radius).ceil(); x++) {
      final dx = x - cx + 0.5;
      final dy = y - cy + 0.5;
      if (dx * dx + dy * dy <= r2) {
        _set(image, x, y, color);
      }
    }
  }
}

/// Fills the upper half of an ellipse, producing a rounded "shoulders" shape.
void _halfEllipse(
  img.Image image,
  double cx,
  double baseY,
  double rx,
  double ry,
  img.Color color,
) {
  for (int y = (baseY - ry).floor(); y <= baseY.ceil(); y++) {
    for (int x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
      final dx = (x - cx + 0.5) / rx;
      final dy = (y - baseY + 0.5) / ry;
      if (dx * dx + dy * dy <= 1.0) {
        _set(image, x, y, color);
      }
    }
  }
}

/// Draws a radial glow that fades from [inner] at the centre to [outer].
void _radial(img.Image image, double cx, double cy, double radius, img.Color inner, img.Color outer) {
  final r2 = radius * radius;
  for (int y = (cy - radius).floor(); y <= (cy + radius).ceil(); y++) {
    for (int x = (cx - radius).floor(); x <= (cx + radius).ceil(); x++) {
      final dx = x - cx + 0.5;
      final dy = y - cy + 0.5;
      final d2 = dx * dx + dy * dy;
      if (d2 > r2) continue;
      final t = d2 / r2;
      final color = img.ColorRgba8(
        (inner.r + (outer.r - inner.r) * t).round(),
        (inner.g + (outer.g - inner.g) * t).round(),
        (inner.b + (outer.b - inner.b) * t).round(),
        (inner.a + (outer.a - inner.a) * t).round(),
      );
      _blend(image, x, y, color);
    }
  }
}

void _set(img.Image image, int x, int y, img.Color color) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
  image.setPixel(x, y, color);
}

/// Alpha-blends [color] over the existing pixel at ([x], [y]).
void _blend(img.Image image, int x, int y, img.Color color) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
  if (color.a >= 255) {
    image.setPixel(x, y, color);
    return;
  }
  final dst = image.getPixel(x, y);
  final a = color.a / 255.0;
  image.setPixel(
    x,
    y,
    img.ColorRgba8(
      (color.r * a + dst.r * (1 - a)).round(),
      (color.g * a + dst.g * (1 - a)).round(),
      (color.b * a + dst.b * (1 - a)).round(),
      255,
    ),
  );
}