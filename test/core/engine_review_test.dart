// Differences found when the engine was read beside the JavaScript (Task 9).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pio_photo_layout/core/export/photo_exporter.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/layout_painter.dart';

import 'render/render_helpers.dart';

LayoutElement _square({double blur = 0, double shadowBlur = 0}) =>
    LayoutElement.create(ElementType.shape)
      ..pin = Pin.top
      ..x = 40
      ..top = 100
      ..w = 100
      ..h = 100
      ..fill = Fill(type: FillType.solid, color: '#FF0000')
      ..effects = Effects(blur: blur)
      ..shadow = ShadowSpec(
          on: true, color: '#0000FF', alpha: 1, blur: shadowBlur, x: 200, y: 0);

Future<Uint8List> _draw(LayoutElement el, double scale) {
  final w = (400 * scale).round(), h = (300 * scale).round();
  return rasterize(w, h, (c) {
    c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    c.scale(scale, scale);
    drawElement(c, el, null, 300);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a filtered piece casts a filtered shadow, as Canvas 2D does',
      (tester) async {
    await tester.runAsync(() async {
      // Chrome, same scene: blue minus red at x = 235 (5 px outside the
      // shadow's sharp edge) is 83, at 245 it is 181 (headless Chrome,
      // ctx.filter blur(10px) with a blur-0 shadow offset 200).
      final px = await _draw(_square(blur: 10), 1);
      int blueness(int x) {
        final p = pixelAt(px, 400, x, 150);
        return p[2] - p[0];
      }

      expect(blueness(235), inInclusiveRange(63, 103));
      expect(blueness(245), inInclusiveRange(161, 201));
    });
  });

  testWidgets('shadow and effect blur scale with the canvas', (tester) async {
    await tester.runAsync(() async {
      final el = _square(shadowBlur: 40);
      final a = await _draw(el, 1);
      final b = await _draw(el, 0.5);
      // 20 design units outside the shadow's edge (x 240), and 20 inside.
      for (final dx in [-20, 20]) {
        final va = pixelAt(a, 400, 240 + dx, 150)[0];
        final vb = pixelAt(b, 200, (240 + dx) ~/ 2, 75)[0];
        expect((va - vb).abs(), lessThan(12), reason: 'dx $dx: $va vs $vb');
      }
      final f = _square(blur: 20)..shadow.on = false;
      final fa = await _draw(f, 1);
      final fb = await _draw(f, 0.5);
      final va = pixelAt(fa, 400, 150, 150)[1];
      final vb = pixelAt(fb, 200, 75, 75)[1];
      expect((va - vb).abs(), lessThan(12), reason: '$va vs $vb');
    });
  });

  testWidgets('a sideways phone photo (EXIF 6) is saved upright', (tester) async {
    await tester.runAsync(() async {
      final bytes = File('test/assets/exif_rotated_6.jpg').readAsBytesSync();
      for (final force in [false, true]) {
        final r = await PhotoExporter(forcePixelPath: force).render(
            bytes, null, null, const ExportSettings(format: OutputFormat.png));
        expect([r.width, r.height], [80, 120], reason: 'pixel path: $force');
        final im = img.decodePng(r.bytes)!;
        expect([im.width, im.height], [80, 120]);
        List<int> at(int x, int y) {
          final p = im.getPixel(x, y);
          return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
        }

        void near(List<int> got, List<int> want, String where) {
          for (var i = 0; i < 3; i++) {
            expect((got[i] - want[i]).abs(), lessThan(30),
                reason: '$where on pixel path $force: $got');
          }
        }

        near(at(8, 8), [230, 20, 20], 'top left');
        near(at(72, 8), [20, 200, 40], 'top right');
        near(at(8, 112), [20, 40, 220], 'bottom left');
        near(at(72, 112), [255, 255, 255], 'bottom right');
      }
    });
  });
}
