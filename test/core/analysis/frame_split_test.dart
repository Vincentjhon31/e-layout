import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/analysis/frame_split.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';

Future<ui.Image> make(int w, int h, void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  draw(ui.Canvas(rec));
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  return img;
}

void bar(ui.Canvas c, double x, double y, double w, double h) => c.drawRect(
    ui.Rect.fromLTWH(x, y, w, h), ui.Paint()..color = const ui.Color(0xFF204080));

Future<ui.Image> frame() => make(1200, 800, (c) {
      bar(c, 0, 0, 1200, 100);
      bar(c, 0, 660, 1200, 140);
      bar(c, 0, 100, 30, 560);
      bar(c, 1170, 100, 30, 560);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('analyseAlpha placements', (tester) async {
    await tester.runAsync(() async {
      final footer = await analyseAlpha(await make(1200, 800, (c) => bar(c, 0, 680, 1200, 120)));
      expect([footer.hasAlpha, footer.placement], [true, 'footer']);
      final header = await analyseAlpha(await make(1200, 800, (c) => bar(c, 0, 0, 1200, 120)));
      expect([header.hasAlpha, header.placement], [true, 'header']);
      final full = await analyseAlpha(await make(1200, 800, (c) => bar(c, 0, 0, 1200, 800)));
      expect([full.hasAlpha, full.placement], [false, 'frame']);
      final mid = await analyseAlpha(await make(600, 600, (c) => bar(c, 200, 280, 200, 40)));
      expect(mid.placement, 'center');
    });
  });

  testWidgets('splitFrame finds four parts, fromParts pins them', (tester) async {
    await tester.runAsync(() async {
      final img = await frame();
      final split = (await splitFrame(img))!;
      final byEdge = {for (final p in split.parts) p.edge: p};
      expect(byEdge.keys.toSet(), {'top', 'bottom', 'left', 'right'});
      expect((byEdge['top']!.h - 100).abs() <= 3, isTrue, reason: '${byEdge['top']!.h}');
      expect((byEdge['bottom']!.h - 140).abs() <= 3, isTrue);
      expect((byEdge['left']!.w - 30).abs() <= 3, isTrue, reason: '${byEdge['left']!.w}');
      expect((byEdge['right']!.w - 30).abs() <= 3, isTrue);
      final parts = await cutParts(img, split);
      expect(parts.length, 4);
      expect(parts.first.png.sublist(1, 4), [0x50, 0x4E, 0x47]);
      final doc = fromParts('x', parts, split.W, split.H);
      expect(doc.elements.map((e) => e.pin).toList(),
          [Pin.top, Pin.bottom, Pin.stretch, Pin.stretch]);
    });
  });

  testWidgets('opaque middle gives null', (tester) async {
    await tester.runAsync(() async {
      expect(await splitFrame(await make(1200, 800, (c) => bar(c, 0, 0, 1200, 800))), isNull);
    });
  });

  testWidgets('softPictures and fitAnyShape', (tester) async {
    await tester.runAsync(() async {
      final small = await make(100, 100, (c) => bar(c, 0, 0, 100, 100));
      final doc = LayoutDoc.blank();
      final prep = LayoutPrep();
      doc.assets['a1'] = LayoutAsset(name: 'p', mime: 'image/png', bytes: Uint8List(0), w: 100, h: 100);
      prep.bitmaps['a1'] = small;
      doc.elements.add(LayoutElement.create(ElementType.image)
        ..asset = 'a1'
        ..fit = ImageFit.stretch
        ..w = 1200
        ..h = 1200);
      final soft = softPictures(doc, prep, 4000, 3);
      expect(soft.length, 1);
      expect([soft.first.natural, soft.first.shown], [100, 4000]);

      // a full-frame picture is split and replaced by four parts
      final fdoc = LayoutDoc.blank();
      final fprep = LayoutPrep();
      final fimg = await frame();
      final bytes = (await fimg.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final id = addAsset(fdoc, name: 'f', mime: 'image/png', bytes: bytes, w: 1200, h: 800);
      fprep.bitmaps[id] = fimg;
      fdoc.elements.add(LayoutElement.create(ElementType.image)
        ..asset = id
        ..fit = ImageFit.stretch
        ..pin = Pin.stretch
        ..w = 1200
        ..h = 800);
      expect(hasFramePicture(fdoc), isTrue);
      final r = await fitAnyShape(fdoc, fprep, 800);
      expect(r.split, 1);
      expect(r.failed, isNull);
      expect(fdoc.elements.length, 4);
      expect(fprep.bitmaps.length, 4); // original + top, bottom, and one shared by identical left and right
    });
  });
}
