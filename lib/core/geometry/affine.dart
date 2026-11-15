import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// 2D affine matrix `[a c e; b d f]`, same letters as DOMMatrix.
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  final double a, b, c, d, e, f;

  static const identity = Affine(1, 0, 0, 1, 0, 0);

  /// `this * o`: [o] applies first, like DOMMatrix.multiply.
  Affine multiply(Affine o) => Affine(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Affine translate(double x, double y) => multiply(Affine(1, 0, 0, 1, x, y));

  Affine rotateDeg(double deg) {
    final r = deg * math.pi / 180;
    var cs = math.cos(r), sn = math.sin(r);
    // Snap right angles so they are exact.
    if ((deg % 90) == 0) {
      cs = cs.abs() < 1e-12 ? 0 : cs.roundToDouble();
      sn = sn.abs() < 1e-12 ? 0 : sn.roundToDouble();
    }
    return multiply(Affine(cs, sn, -sn, cs, 0, 0));
  }

  Affine scale(double sx, double sy) => multiply(Affine(sx, 0, 0, sy, 0, 0));

  Affine? inverted() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12 || !det.isFinite) return null;
    return Affine(
      d / det,
      -b / det,
      -c / det,
      a / det,
      (c * f - d * e) / det,
      (b * e - a * f) / det,
    );
  }

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// Column-major 4x4 for `Canvas.transform`.
  Float64List toMatrix4() =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
}
