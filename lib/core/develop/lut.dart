import 'dart:typed_data';

import 'color_pipeline.dart';

/// A baked 3D colour table. Uploaded as an image `size*size` wide and `size`
/// high; the texel for node indices (r, g, b) is at `x = r + b*size, y = g`.
/// Node i stands for the input value i/(size-1). Values are round(v*255).
class Lut3d {
  Lut3d(this.size, this.rgba);

  final int size;
  final Uint8List rgba;

  int _o(int r, int g, int b) => ((g * size * size) + r + b * size) * 4;

  /// Trilinear lookup, the same maths as the shader: interpolate in r and g
  /// within each of the two neighbouring b slices, then between the slices.
  /// Input is clamped to 0..1; output is 0..1.
  (double, double, double) sample(double r, double g, double b) {
    final n1 = size - 1;
    if (n1 == 0) return (rgba[0] / 255, rgba[1] / 255, rgba[2] / 255);
    double clampScale(double v) =>
        v > 0 ? (v < 1 ? v * n1 : n1.toDouble()) : 0.0;
    final fr = clampScale(r), fg = clampScale(g), fb = clampScale(b);
    var r0 = fr.floor(), g0 = fg.floor(), b0 = fb.floor();
    if (r0 >= n1) r0 = n1 - 1;
    if (g0 >= n1) g0 = n1 - 1;
    if (b0 >= n1) b0 = n1 - 1;
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    final d = rgba;
    double slice(int bi, int c) {
      final o00 = _o(r0, g0, bi) + c;
      final o10 = _o(r0 + 1, g0, bi) + c;
      final o01 = _o(r0, g0 + 1, bi) + c;
      final o11 = _o(r0 + 1, g0 + 1, bi) + c;
      final top = d[o00] + (d[o10] - d[o00]) * tr;
      final bot = d[o01] + (d[o11] - d[o01]) * tr;
      return top + (bot - top) * tg;
    }

    double ch(int c) {
      final a = slice(b0, c);
      final z = slice(b0 + 1, c);
      return (a + (z - a) * tb) / 255;
    }

    return (ch(0), ch(1), ch(2));
  }
}

/// Bakes [p] into a [size]-node-per-side table (17 while dragging, 33 after).
Lut3d bakeLut(ColorPipeline p, int size) {
  final out = Uint8List(size * size * size * 4);
  final inv = 1.0 / (size - 1);
  var o = 0;
  // Row y = g, then x = r + b*size (b-major blocks, r fastest), so a plain
  // sequential write fills the image in raster order.
  for (var g = 0; g < size; g++) {
    final gv = g * inv;
    for (var b = 0; b < size; b++) {
      final bv = b * inv;
      for (var r = 0; r < size; r++) {
        final c = p.apply(r * inv, gv, bv);
        out[o++] = (c.$1 * 255).round().clamp(0, 255);
        out[o++] = (c.$2 * 255).round().clamp(0, 255);
        out[o++] = (c.$3 * 255).round().clamp(0, 255);
        out[o++] = 255;
      }
    }
  }
  return Lut3d(size, out);
}
