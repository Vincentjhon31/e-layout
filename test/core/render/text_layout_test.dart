import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/text_layout.dart';

import 'render_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadBundledFonts);

  test('two-line block', () {
    final el = LayoutElement.create(ElementType.text)
      ..text = 'Hello\nA much longer second line'
      ..size = 40
      ..lineHeight = 1.5;
    final b = layoutText(el);
    expect(b.lines.length, 2);
    expect(b.h, 2 * 40 * 1.5);
    expect(b.w, b.widths[1]);
    expect(b.widths[1] > b.widths[0], isTrue);
  });

  test('upper-cases and never wraps', () {
    final el = LayoutElement.create(ElementType.text)
      ..text = 'abc def ghi jkl mno pqr stu vwx yz'
      ..upper = true;
    expect(layoutText(el).lines, ['ABC DEF GHI JKL MNO PQR STU VWX YZ']);
  });

  test('Flutter adds trailing letter spacing (answer written to the notes)', () {
    final a = LayoutElement.create(ElementType.text)..text = 'AB'..letterSpacing = 0;
    final b = a.clone()..letterSpacing = 40;
    final pa = buildLine(a, 'AB');
    final pb = buildLine(b, 'AB');
    expect(pb.maxIntrinsicWidth - pa.maxIntrinsicWidth, closeTo(80, 0.01));
    // layoutText removes one spacing:
    expect(layoutText(b).widths.first - layoutText(a).widths.first, closeTo(40, 0.01));
  });
}
