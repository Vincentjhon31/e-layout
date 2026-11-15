import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pio_photo_layout/core/codec/jpeg_encoder.dart';
import 'package:pio_photo_layout/core/codec/png_encoder.dart';

Uint8List sample(int w, int h, {int alphaVaries = 0}) {
  final rnd = math.Random(5);
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      b[i] = (x * 255 ~/ w + rnd.nextInt(8)).clamp(0, 255);
      b[i + 1] = (y * 255 ~/ h + rnd.nextInt(8)).clamp(0, 255);
      b[i + 2] = ((x + y) * 255 ~/ (w + h) + rnd.nextInt(8)).clamp(0, 255);
      b[i + 3] = alphaVaries == 1 ? (x * 255 ~/ w) : 255;
    }
  }
  return b;
}

double psnr(Uint8List a, Uint8List b) {
  var se = 0.0;
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final d = (a[i + c] - b[i + c]).toDouble();
      se += d * d;
      n++;
    }
  }
  return 10 * math.log(255 * 255 / (se / n)) / math.ln10;
}

Future<ui.Image> decodeUi(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> rgbaOf(ui.Image i) async =>
    (await i.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('huffman tables are complete', () {
    expect(kAcLumVals.length, kAcLumBits.reduce((a, b) => a + b));
    expect(kAcChrVals.length, kAcChrBits.reduce((a, b) => a + b));
    expect(kAcLumVals.length, 162);
    expect(kAcChrVals.toSet().length, 162);
    expect(kAcLumVals.toSet().length, 162);
  });

  for (final size in [(67, 45), (256, 256)]) {
    final (w, h) = size;
    testWidgets('jpeg ${w}x$h', (tester) async {
      await tester.runAsync(() async {
        final src = sample(w, h);
        final j92 = encodeJpeg(src, w, h, quality: 92);
        final j70 = encodeJpeg(src, w, h, quality: 70);
        expect(j92.sublist(0, 2), [0xFF, 0xD8]);
        expect(j92.sublist(j92.length - 2), [0xFF, 0xD9]);

        final viaUi = await decodeUi(j92);
        expect([viaUi.width, viaUi.height], [w, h]);
        final uiPx = await rgbaOf(viaUi);
        final p92 = psnr(src, uiPx);
        final p70 = psnr(src, await rgbaOf(await decodeUi(j70)));
        expect(p92 >= 34, isTrue, reason: 'psnr92 $p92');
        expect(p70 < p92, isTrue, reason: '$p70 vs $p92');

        final viaImage = img.decodeJpg(j92)!;
        expect([viaImage.width, viaImage.height], [w, h]);
        final ip = viaImage.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
        expect(psnr(src, Uint8List.fromList(ip)) >= 34, isTrue);

        // streaming in bands of 16 rows is byte-identical
        final e = JpegEncoder(width: w, height: h, quality: 92);
        for (var y = 0; y < h; y += 16) {
          final n = math.min(16, h - y);
          e.addRows(Uint8List.sublistView(src, y * w * 4, (y + n) * w * 4), n);
        }
        expect(e.finish(), j92);
      });
    });
  }

  testWidgets('png round trip exact, colour type 2 without alpha', (tester) async {
    await tester.runAsync(() async {
      const w = 53, h = 31;
      final src = sample(w, h, alphaVaries: 1);
      final png = encodePng(src, w, h);
      final out = await rgbaOf(await decodeUi(png));
      // the engine decodes into premultiplied pixels, so colour is exact only
      // where alpha is 255; the size and the alpha channel must still match.
      expect(out.length, src.length);
      for (var i = 0; i < src.length; i += 4) {
        if (src[i + 3] == 255) {
          for (var c = 0; c < 4; c++) {
            expect(out[i + c], src[i + c]);
          }
        } else {
          expect((out[i + 3] - src[i + 3]).abs() <= 1, isTrue);
        }
      }
      // every byte survives a decode with package:image
      final exact = img.decodePng(png)!.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
      for (var i = 0; i < src.length; i++) {
        expect(exact[i], src[i], reason: 'byte $i');
      }
      expect(png[25], 6);
      final rgb = encodePng(sample(w, h), w, h, alpha: false);
      expect(rgb[25], 2);
      final back = img.decodePng(rgb)!;
      expect([back.width, back.height], [w, h]);
      final bp = back.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
      final s = sample(w, h);
      for (var i = 0; i < s.length; i++) {
        expect(bp[i], s[i]);
      }
    });
  });
}
