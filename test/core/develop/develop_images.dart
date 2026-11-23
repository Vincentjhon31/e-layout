// Generated test images and pixel statistics for the developer tests.
// Every image is built in code (gradients, edges, noise, flat patches).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pio_photo_layout/core/develop/photo_developer.dart';

const int kSide = 256;

/// Fills a w x h opaque RGBA buffer from [f] (0..255 per channel).
Uint8List fillRgba(int w, int h, (int, int, int) Function(int x, int y) f) {
  final out = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = f(x, y);
      out[o++] = c.$1.clamp(0, 255);
      out[o++] = c.$2.clamp(0, 255);
      out[o++] = c.$3.clamp(0, 255);
      out[o++] = 255;
    }
  }
  return out;
}

/// Red across, green down, blue on a diagonal: covers most colours.
Uint8List colourfulRgba() =>
    fillRgba(kSide, kSide, (x, y) => (x, y, (x * 3 + y * 5) % 256));

/// A vertical grey edge from [lo] to [hi] (levels), a linear ramp [width] px
/// wide centred on x = 128.
Uint8List softEdgeRgba(int lo, int hi, double width) =>
    fillRgba(kSide, kSide, (x, y) {
      final t = ((x + 0.5 - 128) / width + 0.5).clamp(0.0, 1.0);
      final v = (lo + (hi - lo) * t).round();
      return (v, v, v);
    });

/// Mid grey with independent uniform noise of +-[amp] levels per channel.
Uint8List noiseRgba(int amp, int seed) {
  final rnd = math.Random(seed);
  int n() => 128 + rnd.nextInt(2 * amp + 1) - amp;
  return fillRgba(kSide, kSide, (x, y) => (n(), n(), n()));
}

Uint8List flatRgba(int v) => fillRgba(kSide, kSide, (x, y) => (v, v, v));

/// Gradient, 7 px checker (edges at x = 126 and 133, just past the tile seam)
/// and light noise: detail everywhere.
Uint8List richRgba(int seed) {
  final rnd = math.Random(seed);
  return fillRgba(kSide, kSide, (x, y) {
    final chk = (x ~/ 7 + y ~/ 7).isEven ? 40 : -40;
    final n = rnd.nextInt(21) - 10;
    return (40 + x * 2 ~/ 3 + chk + n, 60 + y ~/ 2 + chk + n, 200 - x ~/ 2 + n);
  });
}

Future<ui.Image> image(Uint8List rgba, [int w = kSide, int h = kSide]) =>
    imageFromRgba(rgba, w, h);

/// Copies the region [x0, x0+w) x [y0, y0+h) of an RGBA buffer.
Uint8List cropRgba(Uint8List src, int srcW, int x0, int y0, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final s = ((y0 + y) * srcW + x0) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, src, s);
  }
  return out;
}

double lumaAt(Uint8List px, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
}

/// Mean and variance of [f] over the rectangle.
(double, double) stats(
  int x0,
  int y0,
  int x1,
  int y1,
  double Function(int x, int y) f,
) {
  var s = 0.0, s2 = 0.0, n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final v = f(x, y);
      s += v;
      s2 += v * v;
      n++;
    }
  }
  final m = s / n;
  return (m, s2 / n - m * m);
}
