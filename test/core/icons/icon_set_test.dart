import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/icons/icon_set.dart';

void main() {
  test('22 icons, has, unknown gives star', () {
    expect(IconSet.names.length, 22);
    expect(IconSet.has('phone'), isTrue);
    expect(IconSet.has('nope'), isFalse);
    expect(identical(IconSet.parts('nope'), IconSet.parts('star')), isTrue);
    expect(IconSet.label('mail'), 'Email');
  });
  test('bounds inside the 24 grid', () {
    final grid = const Rect.fromLTWH(0, 0, 24, 24).inflate(1);
    for (final n in IconSet.names) {
      for (final p in IconSet.parts(n)) {
        final b = p.path.getBounds();
        expect(b.width + b.height > 0, isTrue, reason: n);
        expect(grid.contains(b.topLeft) && grid.contains(b.bottomRight), isTrue,
            reason: n);
      }
    }
  });
  test('youtube is one even-odd fill', () {
    final p = IconSet.parts('youtube');
    expect(p.length, 1);
    expect(p.single.fill && p.single.evenOdd, isTrue);
  });
}
