
import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/geometry/affine.dart';

void main() {
  test('translate then rotate', () {
    final p = Affine.identity.translate(10, 20).rotateDeg(90).apply(const Offset(1, 0));
    expect(p.dx, closeTo(10, 1e-9));
    expect(p.dy, closeTo(21, 1e-9));
  });
  test('inverse', () {
    final m = Affine.identity.translate(5, 7).rotateDeg(33).scale(2, 3);
    final i = m.multiply(m.inverted()!);
    for (final v in [i.a - 1, i.b, i.c, i.d - 1, i.e, i.f]) {
      expect(v.abs() < 1e-9, isTrue);
    }
  });
  test('singular gives null', () {
    expect(const Affine(1, 2, 2, 4, 0, 0).inverted(), isNull);
  });
}
