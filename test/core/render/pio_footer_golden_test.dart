import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/render/layout_painter.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';

import 'render_helpers.dart';

Future<ui.Image> footerOn(int w, int h) async {
  final doc = readLayout(
      jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync()),
      keepIdentity: true);
  upgradePins(doc);
  final prep = await prepareLayout(doc);
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h.toDouble()),
            [const ui.Color(0xFF9EC5E8), const ui.Color(0xFF5E8F5A)]));
  drawLayout(c, doc, prep, h.toDouble());
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  prep.dispose();
  return img;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PIO footer on 1200x800', (tester) async {
    final img = (await tester.runAsync(() async {
      await loadBundledFonts();
      return footerOn(1200, 800);
    }))!;
    await expectLater(img, matchesGoldenFile('goldens/pio_footer_landscape.png'));
  });

  testWidgets('PIO footer on 1200x1600 stays at the bottom', (tester) async {
    final img = (await tester.runAsync(() async {
      await loadBundledFonts();
      return footerOn(1200, 1600);
    }))!;
    await expectLater(img, matchesGoldenFile('goldens/pio_footer_portrait.png'));
  });
}
