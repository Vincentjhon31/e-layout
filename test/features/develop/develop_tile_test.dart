import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/features/develop/develop_canvas.dart';

void main() {
  // A 50 MP photo.
  const photo = Size(8660, 5774);

  void check(
    Rect visible,
    Offset centre,
    int margin,
    double scale, {
    String reason = '',
  }) {
    final t = tilePiece(
      visible: visible,
      centre: centre,
      margin: margin,
      scale: scale,
      photo: photo,
    )!;
    expect(t.width, lessThanOrEqualTo(2048), reason: 'width $reason');
    expect(t.height, lessThanOrEqualTo(2048), reason: 'height $reason');
    // The shown part is inside what is on screen and inside the piece.
    expect(visible.intersect(t.inner), t.inner, reason: reason);
    expect(t.outer.intersect(t.inner), t.inner, reason: reason);
    expect(t.inner.width, greaterThan(0), reason: reason);
    expect(t.inner.height, greaterThan(0), reason: reason);
  }

  test('100 % with a large margin stays within 2048 px, around the centre', () {
    // Clarity on the photo and on a mask, and lens blur at 100.
    const visible = Rect.fromLTWH(3000, 2000, 1170, 1500);
    final centre = visible.center;
    final t = tilePiece(
      visible: visible,
      centre: centre,
      margin: 805,
      scale: 1,
      photo: photo,
    )!;
    expect(t.width, lessThanOrEqualTo(2048));
    expect(t.height, lessThanOrEqualTo(2048));
    expect(t.inner.contains(centre), isTrue);
    expect(t.inner.width, 2048 - 2 * 805);
    expect((t.inner.center - centre).distance, lessThan(1));
  });

  test('a small margin keeps the whole visible part', () {
    const visible = Rect.fromLTWH(3000, 2000, 1170, 1500);
    final t = tilePiece(
      visible: visible,
      centre: visible.center,
      margin: 40,
      scale: 1,
      photo: photo,
    )!;
    expect(t.inner, visible);
    expect(t.outer, const Rect.fromLTRB(2960, 1960, 4210, 3540));
  });

  test('near an edge the part stays inside the visible area', () {
    const visible = Rect.fromLTWH(0, 0, 1170, 1500);
    check(visible, const Offset(40, 30), 805, 1, reason: 'top left');
    const right = Rect.fromLTRB(7490, 4274, 8660, 5774);
    check(right, const Offset(8650, 5770), 805, 1, reason: 'bottom right');
  });

  test('every margin, scale and view size stays within 2048 px', () {
    for (final margin in [0, 100, 512, 805, 960]) {
      for (final scale in [0.5, 0.75, 0.9, 1.0]) {
        for (final side in [600.0, 1170.0, 2400.0, 4000.0]) {
          final visible = Rect.fromLTWH(1000, 500, side, side * 1.2);
          check(
            visible,
            visible.center,
            margin,
            scale,
            reason: 'margin $margin, scale $scale, side $side',
          );
        }
      }
    }
  });

  test('a margin that fills the piece makes no tile', () {
    expect(
      tilePiece(
        visible: const Rect.fromLTWH(0, 0, 500, 500),
        centre: const Offset(250, 250),
        margin: 1024,
        scale: 1,
        photo: photo,
      ),
      isNull,
    );
  });
}
