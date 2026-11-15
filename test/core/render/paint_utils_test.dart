import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/paint_utils.dart';

void main() {
  test('cssFilterMatrix identity for defaults', () {
    expect(cssFilterMatrix(Effects()), [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ]);
    expect(cssFilter(Effects()), isNull);
  });
  test('grayscale 100 first row', () {
    final m = cssFilterMatrix(Effects(grayscale: 100));
    expect(m.sublist(0, 5), [0.2126, 0.7152, 0.0722, 0, 0]);
  });
  test('brightness and contrast', () {
    final m = cssFilterMatrix(Effects(brightness: 50, contrast: 200));
    // contrast(2) after brightness(0.5): 2 * (0.5 x) + 127.5 * (1 - 2)
    expect(m[0], closeTo(1, 1e-9));
    expect(m[4], closeTo(-127.5, 1e-9));
  });
  test('rgba parses', () {
    final c = rgba('#102030', 0.5);
    expect([c.r, c.g, c.b].map((v) => (v * 255).round()), [16, 32, 48]);
    expect(rgba('#zz').toARGB32(), 0xFF000000);
  });
  test('mulberry32 matches the JS generator', () {
    final r = mulberry32(7);
    final got = [for (var i = 0; i < 5; i++) r()];
    const want = [
      0.011704753153026104,
      0.06195825757458806,
      0.97690763277933,
      0.6990287057124078,
      0.5214452685322613,
    ];
    for (var i = 0; i < 5; i++) {
      expect(got[i], closeTo(want[i], 1e-15));
    }
  });
  test('blendOf covers all names', () {
    for (final b in kBlends) {
      expect(blendOf(b), isNotNull);
    }
  });
}
