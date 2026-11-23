import 'dart:typed_data';

/// A 3D colour table (a look), sRGB-encoded 0 to 1 in and out.
///
/// [rgb] holds `size^3 * 3` floats; the entry for grid point (r, g, b) starts
/// at `((b * size + g) * size + r) * 3` (red changes fastest).
class ProfileTable {
  ProfileTable(this.size, this.rgb)
    : assert(size >= 2),
      assert(rgb.length == size * size * size * 3);

  final int size;
  final Float32List rgb;

  /// A table that returns its input.
  static ProfileTable identity(int size) {
    final data = Float32List(size * size * size * 3);
    final d = 1.0 / (size - 1);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          data[i++] = r * d;
          data[i++] = g * d;
          data[i++] = b * d;
        }
      }
    }
    return ProfileTable(size, data);
  }

  /// Trilinear lookup. Inputs are clamped to 0..1.
  (double, double, double) sample(double r, double g, double b) {
    final n = size - 1;
    final fr = (r < 0 ? 0.0 : (r > 1 ? 1.0 : r)) * n;
    final fg = (g < 0 ? 0.0 : (g > 1 ? 1.0 : g)) * n;
    final fb = (b < 0 ? 0.0 : (b > 1 ? 1.0 : b)) * n;
    var r0 = fr.floor(), g0 = fg.floor(), b0 = fb.floor();
    if (r0 >= n) r0 = n - 1;
    if (g0 >= n) g0 = n - 1;
    if (b0 >= n) b0 = n - 1;
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    final sg = size, sb = size * size;
    final base = (b0 * sb + g0 * sg + r0) * 3;
    final t = rgb;
    var or = 0.0, og = 0.0, ob = 0.0;
    for (var k = 0; k < 8; k++) {
      final dr = k & 1, dg = (k >> 1) & 1, db = (k >> 2) & 1;
      final w =
          (dr == 1 ? tr : 1 - tr) *
          (dg == 1 ? tg : 1 - tg) *
          (db == 1 ? tb : 1 - tb);
      if (w == 0) continue;
      final i = base + (db * sb + dg * sg + dr) * 3;
      or += w * t[i];
      og += w * t[i + 1];
      ob += w * t[i + 2];
    }
    return (or, og, ob);
  }
}
