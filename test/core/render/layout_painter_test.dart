import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/render/layout_painter.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';

import 'render_helpers.dart';

void whiteBg(ui.Canvas c, int w, int h) =>
    c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));

LayoutElement rect({double x = 0, double top = 0, double w = 100, double h = 100}) =>
    LayoutElement.create(ElementType.shape)
      ..pin = Pin.top
      ..x = x
      ..top = top
      ..w = w
      ..h = h
      ..fill = Fill(type: FillType.solid, color: '#FF0000');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opacity 0.5 red over white', (tester) async {
    await tester.runAsync(() async {
      await loadBundledFonts();
      final el = rect(x: 50, top: 50)..opacity = 0.5;
      final px = await rasterize(200, 200, (c) {
        whiteBg(c, 200, 200);
        drawElement(c, el, null, 200);
      });
      final p = pixelAt(px, 200, 100, 100);
      expect(p[0], 255);
      expect((p[1] - 128).abs() <= 2, isTrue, reason: '$p');
      expect((p[2] - 128).abs() <= 2, isTrue, reason: '$p');
    });
  });

  testWidgets('shadow offset is in design space, not rotated', (tester) async {
    await tester.runAsync(() async {
      final el = rect(x: 80, top: 80, w: 40, h: 40)
        ..rotation = 90
        ..shadow = ShadowSpec(on: true, color: '#000000', alpha: 1, blur: 0, x: 20, y: 0);
      final px = await rasterize(200, 200, (c) {
        whiteBg(c, 200, 200);
        drawElement(c, el, null, 200);
      });
      final right = pixelAt(px, 200, 130, 100);
      final below = pixelAt(px, 200, 100, 130);
      expect(right[0] < 40 && right[1] < 40, isTrue, reason: 'right $right');
      expect(below, [255, 255, 255, 255], reason: 'below');
    });
  });

  testWidgets('undecodable picture draws nothing and the rest still draws', (tester) async {
    await tester.runAsync(() async {
      final doc = LayoutDoc.blank();
      final id = addAsset(doc,
          name: 'bad',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          w: 10,
          h: 10);
      doc.elements.add(LayoutElement.create(ElementType.image)
        ..asset = id
        ..pin = Pin.top
        ..w = 100
        ..h = 100);
      doc.elements.add(rect(x: 120, top: 0, w: 50, h: 50));
      final prep = await prepareLayout(doc);
      expect(prep.bitmaps, isEmpty);
      final px = await rasterize(200, 200, (c) {
        whiteBg(c, 200, 200);
        drawLayout(c, doc, prep, 200);
      });
      expect(pixelAt(px, 200, 50, 50), [255, 255, 255, 255]);
      expect(pixelAt(px, 200, 140, 20), [255, 0, 0, 255]);
    });
  });

  testWidgets('unknown font falls back and still draws', (tester) async {
    await tester.runAsync(() async {
      final el = LayoutElement.create(ElementType.text)
        ..font = 'Nope Sans'
        ..text = 'Hello'
        ..size = 60
        ..pin = Pin.top
        ..top = 20
        ..w = 300
        ..h = 80
        ..shadow = ShadowSpec(on: false)
        ..fill = Fill(type: FillType.solid, color: '#000000');
      final px = await rasterize(300, 120, (c) {
        whiteBg(c, 300, 120);
        drawElement(c, el, null, 120);
      });
      var dark = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i] < 128) dark++;
      }
      expect(dark > 100, isTrue, reason: 'dark pixels: $dark');
    });
  });

  testWidgets('gradient, icon, effects and blend do not throw', (tester) async {
    await tester.runAsync(() async {
      final g = rect(w: 100, h: 100)
        ..fill = Fill(type: FillType.linear, angle: 45)
        ..effects = Effects(blur: 2, grayscale: 50, brightness: 120)
        ..blend = 'multiply'
        ..skewX = 10
        ..flipX = true;
      final icon = LayoutElement.create(ElementType.icon)
        ..icon = 'youtube'
        ..pin = Pin.top
        ..top = 100
        ..shadow = ShadowSpec(on: true);
      final px = await rasterize(200, 200, (c) {
        whiteBg(c, 200, 200);
        drawElement(c, g, null, 200);
        drawElement(c, icon, null, 200);
      });
      expect(px.length, 200 * 200 * 4);
    });
  });
}
