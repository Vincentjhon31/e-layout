import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pio_photo_layout/core/codec/png_encoder.dart';
import 'package:pio_photo_layout/core/export/photo_exporter.dart';
import 'package:pio_photo_layout/core/model/layout_codec.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/model/layout_ops.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';

import '../render/render_helpers.dart';

Uint8List photoPng(int w, int h, {bool transparent = false}) {
  final b = Uint8List(w * h * 4);
  if (!transparent) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        b[i] = x * 255 ~/ w;
        b[i + 1] = y * 255 ~/ h;
        b[i + 2] = 120;
        b[i + 3] = 255;
      }
    }
  }
  return encodePng(b, w, h);
}

double meanDiff(Uint8List a, Uint8List b) {
  final ia = img.decodeJpg(a)!, ib = img.decodeJpg(b)!;
  expect([ia.width, ia.height], [ib.width, ib.height]);
  final pa = ia.convert(numChannels: 3).getBytes(), pb = ib.convert(numChannels: 3).getBytes();
  var s = 0;
  for (var i = 0; i < pa.length; i++) {
    s += (pa[i] - pb[i]).abs();
  }
  return s / pa.length;
}

Future<LayoutDoc> footerDoc() async => readLayout(
    jsonDecode(File('assets/layouts/pio-footer.layout.json').readAsStringSync()),
    keepIdentity: true)
  ..elements.length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('names', () {
    final used = <String>{};
    expect(uniqueName('a', 'jpg', used), 'a.jpg');
    expect(uniqueName('a', 'jpg', used), 'a (2).jpg');
    expect(uniqueName('A', 'JPG', used), 'A (3).JPG');
    expect(outputStem('IMG 1.JPG', '_PIO?'), 'IMG 1_PIO');
    expect(outputStem('noext', ''), 'noext');
  });

  testWidgets('footer on a 300x200 photo; tiles agree; seams hold', (tester) async {
    await tester.runAsync(() async {
      await loadBundledFonts();
      final doc = await footerDoc();
      upgradePins(doc);
      // a blurred, shadowed shape lying across the tile seams (x = 64, 128)
      doc.elements.add(LayoutElement.create(ElementType.shape)
        ..pin = Pin.top
        ..x = 150
        ..top = 100
        ..w = 600
        ..h = 300
        ..fill = Fill(type: FillType.solid, color: '#CC2222')
        ..effects = Effects(blur: 6)
        ..shadow = ShadowSpec(on: true, color: '#000000', alpha: 0.6, blur: 60, x: 30, y: 30));
      final prep = await prepareLayout(doc);
      final photo = photoPng(300, 200);
      const s = ExportSettings();
      final big = await PhotoExporter(tileSize: 4096).render(photo, doc, prep, s);
      expect([big.width, big.height, big.ext], [300, 200, 'jpg']);
      expect(img.decodeJpg(big.bytes)!.width, 300);
      final small = await PhotoExporter(tileSize: 64).render(photo, doc, prep, s);
      final d = meanDiff(big.bytes, small.bytes);
      expect(d < 1.0, isTrue, reason: 'mean diff $d');
      final px = await PhotoExporter(tileSize: 64, forcePixelPath: true).render(photo, doc, prep, s);
      final d2 = meanDiff(big.bytes, px.bytes);
      expect(d2 < 1.0, isTrue, reason: 'pixel path diff $d2');
      prep.dispose();
    });
  });

  testWidgets('transparent photo as JPEG is white; PNG keeps alpha', (tester) async {
    await tester.runAsync(() async {
      final photo = photoPng(64, 64, transparent: true);
      final r = await PhotoExporter().render(photo, null, null, const ExportSettings());
      final px = img.decodeJpg(r.bytes)!.getPixel(32, 32);
      expect([px.r, px.g, px.b].every((v) => v >= 252), isTrue, reason: '$px');
      final p = await PhotoExporter()
          .render(photo, null, null, const ExportSettings(format: OutputFormat.png));
      expect(p.ext, 'png');
      expect(img.decodePng(p.bytes)!.getPixel(32, 32).a, 0);
    });
  });

  testWidgets('crop layout of ratio 1 gives 200x200', (tester) async {
    await tester.runAsync(() async {
      final doc = LayoutDoc.blank()
        ..fit = DocFit.crop
        ..ratio = 1;
      final r = await PhotoExporter().render(photoPng(300, 200), doc, null, const ExportSettings());
      expect([r.width, r.height], [200, 200]);
      final px = await PhotoExporter(forcePixelPath: true)
          .render(photoPng(300, 200), doc, null, const ExportSettings());
      expect([px.width, px.height], [200, 200]);
      expect(meanDiff(r.bytes, px.bytes) < 1.0, isTrue);
    });
  });
}
