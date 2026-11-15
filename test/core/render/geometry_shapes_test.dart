import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/photo_geometry.dart';
import 'package:pio_photo_layout/core/render/shape_paths.dart';

void main() {
  test('photoGeometry landscape keep', () {
    final g = photoGeometry(4000, 3000, null);
    expect([g.w, g.h], [4000, 3000]);
    expect(g.s, 4000 / 1200);
    expect(g.frameH, 900);
  });
  test('photoGeometry crop ratio 1', () {
    final doc = LayoutDoc.blank()
      ..fit = DocFit.crop
      ..ratio = 1;
    final g = photoGeometry(4000, 3000, doc);
    expect([g.w, g.h, g.cropX, g.cropY, g.frameH], [3000, 3000, 500, 0, 1200]);
  });
  test('shape bounds inside the box', () {
    for (final k in ShapeKind.values) {
      final el = LayoutElement.create(ElementType.shape)
        ..shape = k
        ..radius = 30;
      final b = shapePath(el, 240, 160).getBounds();
      expect(b.left >= -0.001 && b.top >= -0.001, isTrue, reason: '$k');
      expect(b.right <= 240.001 && b.bottom <= 160.001, isTrue, reason: '$k');
      expect(b.width > 0 && b.height > 0, isTrue, reason: '$k');
    }
  });
}
